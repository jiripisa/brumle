// BrumleAU.cpp - the Brumle instrument as an Audio Unit (AUv2 music device).
//
// A thin layer over the sound engine (BrumleDSP): it publishes the keyboard set's parameters and
// the built-in programs to the host, forwards MIDI and renders. Audio Unit parameter values are
// the engine's "plain" values (s, Hz, ms, dB, %, an index), so automation and saved host projects
// read naturally. The pads, their notes and groups and the mode are no parameters: the plug-in's
// window sets them on the engine directly (kBrumleProperty_Engine), and they are saved with the
// unit's state. Built on Apple's AudioUnitSDK.

#include "BrumleAU.h"
#include "BrumleDSP.h"

#include <AudioUnitSDK/MusicDeviceBase.h>

#include <algorithm>
#include <cstring>
#include <vector>

namespace {

// Groups shown by hosts that draw a generic parameter view ("clumps"): the engine's sections,
// the same as the app's panels. Clump 0 means "no group", so section n is clump n + 1.
UInt32 clumpOf(const BrumleParamInfo& info) { return static_cast<UInt32>(info.section) + 1; }

AudioUnitParameterUnit unitOf(const BrumleParamInfo& info)
{
    if (info.kind == BRUMLE_KIND_CHOICE) return kAudioUnitParameterUnit_Indexed;
    if (!std::strcmp(info.unit, "s"))  return kAudioUnitParameterUnit_Seconds;
    if (!std::strcmp(info.unit, "Hz")) return kAudioUnitParameterUnit_Hertz;
    if (!std::strcmp(info.unit, "dB")) return kAudioUnitParameterUnit_Decibels;
    if (!std::strcmp(info.unit, "ms")) return kAudioUnitParameterUnit_Milliseconds;
    if (!std::strcmp(info.unit, "%"))  return kAudioUnitParameterUnit_Percent;
    if (!std::strcmp(info.unit, "st")) return kAudioUnitParameterUnit_RelativeSemiTones;
    if (!std::strcmp(info.unit, "ct")) return kAudioUnitParameterUnit_Cents;
    return kAudioUnitParameterUnit_Generic;
}

// The built-in programs as AUPresets. The table lives for the life of the process.
const std::vector<AUPreset>& factoryPresets()
{
    static const std::vector<AUPreset> presets = [] {
        std::vector<AUPreset> v;
        for (int i = 0; i < brumle_num_programs(); ++i)
            v.push_back(AUPreset{ i, CFStringCreateWithCString(nullptr, brumle_program_name(i), kCFStringEncodingUTF8) });
        return v;
    }();
    return presets;
}

// The longest a note can ring: the top of the Ring knob, in seconds.
Float64 longestRing()
{
    for (int i = 0; i < brumle_num_params(); ++i)
    {
        BrumleParamInfo info{};
        brumle_param_info(i, &info);
        if (!std::strcmp(info.identifier, "ring")) return info.maxValue;
    }
    return 0.0;
}

// ----- the pads in the saved state ----------------------------------------------------------
// The base class saves the unit's parameters (the keyboard set). The program the keyboard set
// last loaded, the pads and the mode ride along under a key of their own:
//   "brumle-pads": { "mode": int, "keyboardProgram": int,
//                    "pads": [ 16 × { "note": int, "group": int (0 = Off), "program": int,
//                                     "values": data: Float32 plain values by parameter index } ] }

CFStringRef padsKey() { return CFSTR("brumle-pads"); }

void setInt(CFMutableDictionaryRef dict, CFStringRef key, SInt32 value)
{
    CFNumberRef number = CFNumberCreate(nullptr, kCFNumberSInt32Type, &value);
    CFDictionarySetValue(dict, key, number);
    CFRelease(number);
}

// The int under `key`; false if there is none.
bool getInt(CFDictionaryRef dict, CFStringRef key, int& out)
{
    const void* value = CFDictionaryGetValue(dict, key);
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID()) return false;
    SInt32 number = 0;
    if (!CFNumberGetValue(static_cast<CFNumberRef>(value), kCFNumberSInt32Type, &number)) return false;
    out = number;
    return true;
}

CFDictionaryRef copyPad(BrumleEngine* engine, int pad)
{
    const int set = pad + 1;
    CFMutableDictionaryRef dict = CFDictionaryCreateMutable(nullptr, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    setInt(dict, CFSTR("note"), brumle_pad_note(engine, pad));
    setInt(dict, CFSTR("group"), brumle_pad_group(engine, pad));
    setInt(dict, CFSTR("program"), brumle_get_program(engine, set));
    std::vector<Float32> values(static_cast<size_t>(brumle_num_params()));
    for (size_t i = 0; i < values.size(); ++i) values[i] = brumle_get_plain(engine, set, static_cast<int>(i));
    CFDataRef data = CFDataCreate(nullptr, reinterpret_cast<const UInt8*>(values.data()),
                                  static_cast<CFIndex>(values.size() * sizeof(Float32)));
    CFDictionarySetValue(dict, CFSTR("values"), data);
    CFRelease(data);
    return dict;
}

// What is missing from a saved pad stays as it is. A list of values from a version with fewer
// parameters covers the first of them; the table only ever grows at its end.
void restorePad(BrumleEngine* engine, int pad, CFDictionaryRef dict)
{
    const int set = pad + 1;
    int number = 0;
    if (getInt(dict, CFSTR("note"), number)) brumle_set_pad_note(engine, pad, number);
    if (getInt(dict, CFSTR("group"), number)) brumle_set_pad_group(engine, pad, number);

    const int count = brumle_num_params();
    const void* stored = CFDictionaryGetValue(dict, CFSTR("values"));
    CFDataRef data = stored && CFGetTypeID(stored) == CFDataGetTypeID() ? static_cast<CFDataRef>(stored) : nullptr;
    const int saved = data ? std::min(count, static_cast<int>(CFDataGetLength(data) / static_cast<CFIndex>(sizeof(Float32)))) : 0;

    // Loading a program overwrites the whole set: the knobs the state has no value for are
    // taken away first and put back after.
    int program = 0;
    if (getInt(dict, CFSTR("program"), program) && program != brumle_get_program(engine, set))
    {
        std::vector<float> kept(static_cast<size_t>(count));
        for (int i = saved; i < count; ++i) kept[static_cast<size_t>(i)] = brumle_get_normalised(engine, set, i);
        brumle_set_program(engine, set, program);
        for (int i = saved; i < count; ++i) brumle_set_normalised(engine, set, i, kept[static_cast<size_t>(i)]);
    }
    const UInt8* bytes = data ? CFDataGetBytePtr(data) : nullptr;
    for (int i = 0; i < saved; ++i)
    {
        Float32 value = 0;
        std::memcpy(&value, bytes + static_cast<size_t>(i) * sizeof(Float32), sizeof value);   // CFData need not be aligned
        brumle_set_plain(engine, set, i, value);
    }
}

} // namespace

class BrumleAU : public ausdk::MusicDeviceBase {
    using Base = ausdk::MusicDeviceBase;

public:
    explicit BrumleAU(AudioComponentInstance instance)
        : Base{ instance, 0, 1 }, engine_(brumle_create()), tail_(longestRing())
    {
        CreateElements();
        const int count = brumle_num_params();
        Globals()->UseIndexedParameters(static_cast<UInt32>(count));
        applied_.resize(static_cast<size_t>(count));
        for (int i = 0; i < count; ++i)
        {
            BrumleParamInfo info{};
            brumle_param_info(i, &info);
            Globals()->SetParameter(static_cast<AudioUnitParameterID>(i), info.defaultValue);
            applied_[static_cast<size_t>(i)] = info.defaultValue;
        }
        SetAFactoryPresetAsCurrent(factoryPresets().front());
    }

    ~BrumleAU() override { brumle_destroy(engine_); }

    // ----- formats --------------------------------------------------------------------------
    bool StreamFormatWritable(AudioUnitScope, AudioUnitElement) override { return !IsInitialized(); }
    bool CanScheduleParameters() const noexcept AUSDK_RTSAFE override { return false; }

    UInt32 SupportedNumChannels(const AUChannelInfo** outInfo) override
    {
        static const AUChannelInfo configurations[] = { { 0, 2 }, { 0, 1 } };   // no input; stereo or mono out
        if (outInfo) *outInfo = configurations;
        return 2;
    }

    OSStatus Initialize() override
    {
        const AudioStreamBasicDescription& format = Output(0).GetStreamFormat();
        if (format.mChannelsPerFrame < 1 || format.mChannelsPerFrame > 2) return kAudioUnitErr_FormatNotSupported;
        brumle_prepare(engine_, format.mSampleRate);
        latency_ = format.mSampleRate > 0 ? brumle_latency(engine_) / format.mSampleRate : 0.0;
        // A mono output gets both sides mixed: the engine renders stereo into these first. Made
        // here, never while rendering; the host cannot raise the frames per slice until the
        // unit is uninitialised.
        const size_t scratch = format.mChannelsPerFrame == 1 ? GetMaxFramesPerSlice() : 0;
        scratchLeft_.assign(scratch, 0.0f);
        scratchRight_.assign(scratch, 0.0f);
        return noErr;
    }

    OSStatus Reset(AudioUnitScope scope, AudioUnitElement element) override
    {
        brumle_request_reset(engine_);     // left to the render thread: a host may reset while it renders
        return Base::Reset(scope, element);
    }

    // Output lags MIDI by the engine's decimator below 88.2 kHz; a note rings at most as long as
    // the longest Ring.
    Float64 GetLatency() AUSDK_RTSAFE override { return latency_; }
    bool SupportsTail() AUSDK_RTSAFE override { return true; }
    Float64 GetTailTime() AUSDK_RTSAFE override { return tail_; }

    // ----- properties -----------------------------------------------------------------------
    // A host asks for the plug-in's own window through the CocoaUI property: the bundle and the
    // name of a class in it that makes the view (BrumleAUViewFactory). Without the component
    // bundle (the unit registered in a process by hand) there is none, and the host shows its
    // generic parameter view. The unit's own properties are described in BrumleAU.h.
    OSStatus GetPropertyInfo(AudioUnitPropertyID id, AudioUnitScope scope, AudioUnitElement element,
                             UInt32& outDataSize, bool& outWritable) override
    {
        if (scope == kAudioUnitScope_Global)
        {
            switch (id)
            {
                case kAudioUnitProperty_CocoaUI:
                    if (!CFBundleGetBundleWithIdentifier(CFSTR(BRUMLE_AU_BUNDLE_ID))) return kAudioUnitErr_InvalidProperty;
                    outDataSize = sizeof(AudioUnitCocoaViewInfo);
                    outWritable = false;
                    return noErr;
                case kBrumleProperty_Engine:
                    outDataSize = sizeof(BrumleEngine*);
                    outWritable = false;
                    return noErr;
                case kBrumleProperty_StateChanged:
                    outDataSize = sizeof(UInt32);
                    outWritable = true;
                    return noErr;
                default:
                    break;
            }
        }
        return Base::GetPropertyInfo(id, scope, element, outDataSize, outWritable);
    }

    OSStatus GetProperty(AudioUnitPropertyID id, AudioUnitScope scope, AudioUnitElement element, void* outData) override
    {
        if (scope == kAudioUnitScope_Global)
        {
            switch (id)
            {
                case kAudioUnitProperty_CocoaUI:
                {
                    CFBundleRef bundle = CFBundleGetBundleWithIdentifier(CFSTR(BRUMLE_AU_BUNDLE_ID));
                    if (!bundle) return kAudioUnitErr_InvalidProperty;
                    auto* info = static_cast<AudioUnitCocoaViewInfo*>(outData);
                    info->mCocoaAUViewBundleLocation = CFBundleCopyBundleURL(bundle);       // the host releases both
                    info->mCocoaAUViewClass[0] = CFStringCreateWithCString(nullptr, BRUMLE_AU_VIEW_CLASS, kCFStringEncodingUTF8);
                    return noErr;
                }
                case kBrumleProperty_Engine:
                    *static_cast<BrumleEngine**>(outData) = engine_;
                    return noErr;
                case kBrumleProperty_StateChanged:
                    return kAudioUnitErr_InvalidPropertyValue;     // written, never read
                default:
                    break;
            }
        }
        return Base::GetProperty(id, scope, element, outData);
    }

    OSStatus SetProperty(AudioUnitPropertyID id, AudioUnitScope scope, AudioUnitElement element,
                         const void* inData, UInt32 inDataSize) override
    {
        if (scope == kAudioUnitScope_Global)
        {
            if (id == kBrumleProperty_Engine) return kAudioUnitErr_PropertyNotWritable;
            if (id == kBrumleProperty_StateChanged)
            {
                if (inDataSize != sizeof(UInt32)) return kAudioUnitErr_InvalidPropertyValue;
                PropertyChanged(kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, 0);
                return noErr;
            }
        }
        return Base::SetProperty(id, scope, element, inData, inDataSize);
    }

    // ----- saved state ----------------------------------------------------------------------
    OSStatus SaveState(CFPropertyListRef* outData) override
    {
        const OSStatus status = Base::SaveState(outData);
        if (status != noErr || !outData || !*outData || CFGetTypeID(*outData) != CFDictionaryGetTypeID()) return status;
        CFMutableDictionaryRef pads = CFDictionaryCreateMutable(nullptr, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        setInt(pads, CFSTR("mode"), brumle_get_mode(engine_));
        setInt(pads, CFSTR("keyboardProgram"), brumle_get_program(engine_, BRUMLE_KEYBOARD_SET));
        CFMutableArrayRef list = CFArrayCreateMutable(nullptr, BRUMLE_NUM_PADS, &kCFTypeArrayCallBacks);
        for (int pad = 0; pad < BRUMLE_NUM_PADS; ++pad)
        {
            CFDictionaryRef saved = copyPad(engine_, pad);
            CFArrayAppendValue(list, saved);
            CFRelease(saved);
        }
        CFDictionarySetValue(pads, CFSTR("pads"), list);
        CFRelease(list);
        // The base class made this dictionary a moment ago and nobody else holds it yet.
        CFDictionarySetValue(static_cast<CFMutableDictionaryRef>(const_cast<void*>(*outData)), padsKey(), pads);
        CFRelease(pads);
        return noErr;
    }

    // State without the pads leaves them alone (the default kit); a shorter list of pads leaves
    // the rest alone. Whatever is missing or of the wrong type is left as it is. The keyboard
    // set's values came with the base class's parameters: of its program only the number is put
    // back, so that a reset to the program's value finds the right program.
    OSStatus RestoreState(CFPropertyListRef plist) override
    {
        const OSStatus status = Base::RestoreState(plist);
        if (status != noErr || !plist || CFGetTypeID(plist) != CFDictionaryGetTypeID()) return status;
        const void* stored = CFDictionaryGetValue(static_cast<CFDictionaryRef>(plist), padsKey());
        if (!stored || CFGetTypeID(stored) != CFDictionaryGetTypeID()) return status;
        const auto pads = static_cast<CFDictionaryRef>(stored);

        int mode = 0;
        if (getInt(pads, CFSTR("mode"), mode)) brumle_set_mode(engine_, mode);
        int program = 0;
        if (getInt(pads, CFSTR("keyboardProgram"), program)) brumle_set_program_index(engine_, BRUMLE_KEYBOARD_SET, program);
        const void* list = CFDictionaryGetValue(pads, CFSTR("pads"));
        if (!list || CFGetTypeID(list) != CFArrayGetTypeID()) return status;
        const auto array = static_cast<CFArrayRef>(list);
        const int count = std::min(static_cast<int>(CFArrayGetCount(array)), static_cast<int>(BRUMLE_NUM_PADS));
        for (int pad = 0; pad < count; ++pad)
        {
            const void* saved = CFArrayGetValueAtIndex(array, pad);
            if (saved && CFGetTypeID(saved) == CFDictionaryGetTypeID()) restorePad(engine_, pad, static_cast<CFDictionaryRef>(saved));
        }
        return status;
    }

    // ----- parameters -----------------------------------------------------------------------
    OSStatus GetParameterInfo(AudioUnitScope scope, AudioUnitParameterID id, AudioUnitParameterInfo& out) override
    {
        if (scope != kAudioUnitScope_Global) return kAudioUnitErr_InvalidScope;
        if (id >= static_cast<AudioUnitParameterID>(brumle_num_params())) return kAudioUnitErr_InvalidParameter;
        BrumleParamInfo info{};
        brumle_param_info(static_cast<int>(id), &info);

        out.flags = kAudioUnitParameterFlag_IsReadable | kAudioUnitParameterFlag_IsWritable;
        FillInParameterName(out, CFStringCreateWithCString(nullptr, info.name, kCFStringEncodingUTF8), true);
        if (info.section >= 0) HasClump(out, clumpOf(info));     // the LFO and VEL amounts are in none
        out.unit = unitOf(info);
        out.minValue = info.minValue;
        out.maxValue = info.maxValue;
        out.defaultValue = info.defaultValue;
        if (info.logarithmic) out.flags |= kAudioUnitParameterFlag_DisplayLogarithmic;
        return noErr;
    }

    OSStatus GetParameterValueStrings(AudioUnitScope scope, AudioUnitParameterID id, CFArrayRef* outStrings) override
    {
        if (scope != kAudioUnitScope_Global) return kAudioUnitErr_InvalidScope;
        if (id >= static_cast<AudioUnitParameterID>(brumle_num_params())) return kAudioUnitErr_InvalidParameter;
        BrumleParamInfo info{};
        brumle_param_info(static_cast<int>(id), &info);
        if (info.numChoices <= 0) return kAudioUnitErr_InvalidProperty;
        if (!outStrings) return noErr;                       // the host only asked whether there are any
        CFMutableArrayRef names = CFArrayCreateMutable(nullptr, info.numChoices, &kCFTypeArrayCallBacks);
        for (int c = 0; c < info.numChoices; ++c)
        {
            CFStringRef name = CFStringCreateWithCString(nullptr, brumle_param_choice(static_cast<int>(id), c), kCFStringEncodingUTF8);
            CFArrayAppendValue(names, name);
            CFRelease(name);
        }
        *outStrings = names;
        return noErr;
    }

    OSStatus CopyClumpName(AudioUnitScope, UInt32 clump, UInt32, CFStringRef* outName) override
    {
        if (clump < 1 || clump > static_cast<UInt32>(brumle_num_sections())) return kAudioUnitErr_InvalidPropertyValue;
        *outName = CFStringCreateWithCString(nullptr, brumle_section_name(static_cast<int>(clump) - 1), kCFStringEncodingUTF8);
        return noErr;
    }

    // ----- factory presets (the engine's built-in programs) ---------------------------------
    OSStatus GetPresets(CFArrayRef* outData) const override
    {
        if (!outData) return noErr;
        const std::vector<AUPreset>& presets = factoryPresets();
        CFMutableArrayRef array = CFArrayCreateMutable(nullptr, static_cast<CFIndex>(presets.size()), nullptr);
        for (const AUPreset& p : presets) CFArrayAppendValue(array, &p);
        *outData = array;
        return noErr;
    }

    // A program loads into the keyboard set, as the unit's parameters are; the pads keep theirs.
    // Only the render thread touches what it last handed to the engine (applied_): it sees the
    // parameters change as it sees any host change and sets the values the program just put in.
    OSStatus NewFactoryPresetSet(const AUPreset& preset) override
    {
        const SInt32 number = preset.presetNumber;
        if (number < 0 || number >= brumle_num_programs()) return kAudioUnitErr_InvalidPropertyValue;
        brumle_set_program(engine_, BRUMLE_KEYBOARD_SET, number);
        for (int i = 0; i < brumle_num_params(); ++i)
        {
            if (!brumle_program_sets(i)) continue;           // Octave stays where the player put it
            Globals()->SetParameter(static_cast<AudioUnitParameterID>(i), brumle_program_value(number, i));
        }
        SetAFactoryPresetAsCurrent(factoryPresets()[static_cast<size_t>(number)]);
        return noErr;
    }

    // ----- MIDI -----------------------------------------------------------------------------
    // Everything goes to the engine as raw MIDI. A host may call this on the render thread or on
    // another one, so the event is posted, which is safe and lock-free on either.
    OSStatus HandleMIDIEvent(UInt8 status, UInt8 channel, UInt8 data1, UInt8 data2, UInt32 offsetFrames) AUSDK_RTSAFE override
    {
        brumle_post_midi(engine_, status | channel, data1, data2, static_cast<int>(offsetFrames));
        return noErr;
    }

    // ----- render ---------------------------------------------------------------------------
    OSStatus Render(AudioUnitRenderActionFlags&, const AudioTimeStamp&, UInt32 frames) AUSDK_RTSAFE override
    {
        // Parameters the host or its automation changed since the last block.
        const int count = static_cast<int>(applied_.size());
        for (int i = 0; i < count; ++i)
        {
            const float value = Globals()->GetParameter(static_cast<AudioUnitParameterID>(i));
            if (value != applied_[static_cast<size_t>(i)])
            {
                applied_[static_cast<size_t>(i)] = value;
                brumle_set_plain(engine_, BRUMLE_KEYBOARD_SET, i, value);
            }
        }

        AudioBufferList& buffers = Output(0).GetBufferList();
        float* left = static_cast<float*>(buffers.mBuffers[0].mData);
        if (buffers.mNumberBuffers > 1)
        {
            brumle_process(engine_, left, static_cast<float*>(buffers.mBuffers[1].mData), static_cast<int>(frames));
            return noErr;
        }

        // Mono: (L + R) / 2, so that a voice panned to one side is still heard.
        const UInt32 room = static_cast<UInt32>(scratchLeft_.size());
        if (room == 0) return kAudioUnitErr_Uninitialized;
        for (UInt32 done = 0; done < frames;)
        {
            const UInt32 n = std::min(room, frames - done);
            brumle_process(engine_, scratchLeft_.data(), scratchRight_.data(), static_cast<int>(n));
            for (UInt32 i = 0; i < n; ++i) left[done + i] = 0.5f * (scratchLeft_[i] + scratchRight_[i]);
            done += n;
        }
        return noErr;
    }

private:
    BrumleEngine* engine_;
    std::vector<float> applied_;          // the plain value last handed to the engine, per parameter
    std::vector<float> scratchLeft_;      // stereo for a mono output, made in Initialize
    std::vector<float> scratchRight_;
    Float64 latency_ = 0.0;               // seconds, as of the last Initialize
    const Float64 tail_;                  // seconds
};

AUSDK_COMPONENT_ENTRY(ausdk::AUMusicDeviceFactory, BrumleAU)
