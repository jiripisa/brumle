// BrumleEngine.cpp - the Brumle sound engine and its C interface.
//
// One engine is a pool of voices (Voice.h), each a plucked reed, and seventeen knob sets: the
// keyboard's and one per pad. In keyboard mode every note plays the keyboard set at its own
// pitch, one voice per note number: the same note again chokes its own ring and plucks anew.
//
//   voices -> sum (L, R) -> DC blocker -> kLevel -> limiter -> out
//
// Still to come in this phase: modulation (LFOs, VEL amounts, wheels), pad mode, voice stealing
// and oversampling below 88.2 kHz. Until then the voices run at the host rate.

// A product and a sum stay two roundings. An optimised build would otherwise fuse them into one
// multiply-add where a debug build does not, and the two builds would render different last
// bits: the engine's sound must be the same in both, and the same as the references it is
// tested against.
#pragma clang fp contract(off)

#include "BrumleDSP.h"
#include "MidiQueue.h"
#include "Params.h"
#include "Voice.h"

#include <atomic>
#include <cstdio>
#include <cstring>
#include <random>

using namespace brumle;

namespace {

bool validSet(int set) { return set >= 0 && set < BRUMLE_NUM_SETS; }
bool validPad(int pad) { return pad >= 0 && pad < BRUMLE_NUM_PADS; }

// Didgeridoo's tanh: a Padé approximant, exact enough for a limiter and cheap.
inline float fastTanh(float x)
{
    if (x > 4.97f) return 1.0f;
    if (x < -4.97f) return -1.0f;
    const float x2 = x * x;
    const float a = x * (135135.0f + x2 * (17325.0f + x2 * (378.0f + x2)));
    const float b = 135135.0f + x2 * (62370.0f + x2 * (3150.0f + x2 * 28.0f));
    return a / b;
}

} // namespace

// ---------------------------------------------------------------------------------------------
// The engine
// ---------------------------------------------------------------------------------------------
struct BrumleEngine
{
    BrumleEngine()
    {
        for (int s = 0; s < BRUMLE_NUM_SETS; ++s)
            for (int i = 0; i < kNumParams; ++i) sets_[s][i].store(param(i).toNormalised(param(i).def), std::memory_order_relaxed);
        for (int pad = 0; pad < BRUMLE_NUM_PADS; ++pad)
        {
            padNote_[pad].store(BRUMLE_FIRST_PAD_NOTE + pad, std::memory_order_relaxed);
            padGroup_[pad].store(0, std::memory_order_relaxed);
        }
        prepare(44100.0);
    }

    // ----- knob sets (any thread) ---------------------------------------------------------
    float getNormalised(int set, int i) const { return sets_[set][i].load(std::memory_order_relaxed); }
    float get(int set, int i) const { return param(i).toPlain(getNormalised(set, i)); }
    void  setNormalised(int set, int i, float v)
    {
        if (std::isnan(v)) return;
        sets_[set][i].store(std::clamp(v, 0.0f, 1.0f), std::memory_order_relaxed);
    }
    void  set(int set, int i, float plain) { if (!std::isnan(plain)) setNormalised(set, i, param(i).toNormalised(plain)); }

    void setProgram(int set, int index)
    {
        if (index < 0 || index >= (int)programs().size()) return;
        program_[set].store(index, std::memory_order_relaxed);
        const Program& p = programs()[(size_t)index];
        for (int i = 0; i < kNumParams; ++i)
            if (programSets(i)) this->set(set, i, p.values[i]);
    }
    int program(int set) const { return program_[set].load(std::memory_order_relaxed); }

    void setMode(int mode)
    {
        if (mode == BRUMLE_MODE_KEYBOARD || mode == BRUMLE_MODE_PADS) mode_.store(mode, std::memory_order_relaxed);
    }
    int mode() const { return mode_.load(std::memory_order_relaxed); }

    int  padNote(int pad) const { return padNote_[pad].load(std::memory_order_relaxed); }
    void setPadNote(int pad, int note) { if (note >= 0 && note <= 127) padNote_[pad].store(note, std::memory_order_relaxed); }
    int  padGroup(int pad) const { return padGroup_[pad].load(std::memory_order_relaxed); }
    void setPadGroup(int pad, int group) { if (group >= 0 && group <= BRUMLE_NUM_GROUPS) padGroup_[pad].store(group, std::memory_order_relaxed); }

    int lastNote() const { return lastNote_.load(std::memory_order_relaxed); }
    int soundingVoices() const { return sounding_.load(std::memory_order_relaxed); }

    void requestReset() { resetPending_.store(true, std::memory_order_release); }   // any thread

    // ----- MIDI ---------------------------------------------------------------------------
    void postMidi(uint8_t status, uint8_t d1, uint8_t d2, int offset) { posted_.post(status, d1, d2, offset); }   // any thread

    void midi(uint8_t status, uint8_t d1, uint8_t d2, int offset)   // audio thread
    {
        if (numEvents_ >= kMaxEvents) return;
        int i = numEvents_++;                                       // keep the list sorted by offset
        while (i > 0 && events_[i - 1].sampleOffset > offset) { events_[i] = events_[i - 1]; --i; }
        events_[i] = MidiEvent{ offset < 0 ? 0 : offset, status, d1, d2 };
    }

    // ----- lifecycle ----------------------------------------------------------------------
    void prepare(double sampleRate)
    {
        if (!(sampleRate > 0.0) || !std::isfinite(sampleRate)) return;
        hostRate_ = sampleRate;
        internalRate_ = sampleRate;
        dcCoeff_ = (float)(1.0 - 48.0 / internalRate_);    // 0.9995 at 96 kHz, the prototype's
        reset();
    }

    void reset()
    {
        for (Voice& v : voices_) v = Voice();
        rng_.seed(12345);
        for (int& d : lastDir_) d = -1;
        dcL_ = dcR_ = Dc{};
        sounding_.store(0, std::memory_order_relaxed);
    }

    void process(float* left, float* right, int frames)
    {
        if (resetPending_.exchange(false, std::memory_order_acq_rel)) reset();

        // MIDI posted from other threads joins this block at its sample offset.
        posted_.drain([this](const MidiEvent& e) { midi(e.status, e.data1, e.data2, e.sampleOffset); });

        readKeyboardSet();

        // Sample-accurate MIDI: render up to each event, then apply it.
        int pos = 0;
        for (int e = 0; e < numEvents_; ++e)
        {
            const int offset = std::clamp(events_[e].sampleOffset, 0, frames);
            if (offset > pos) { render(left, right, pos, offset); pos = offset; }
            handleMidi(events_[e]);
        }
        render(left, right, pos, frames);
        numEvents_ = 0;

        int sounding = 0;
        for (const Voice& v : voices_) if (v.active && !v.choking) ++sounding;
        sounding_.store(sounding, std::memory_order_relaxed);
    }

private:
    static constexpr int kNumSlots = 20;         // voice slots (Task 6 lets at most 16 sound)
    static constexpr int kMaxEvents = 256;

    // The output scale. The default hit at full velocity (C2, velocity 127, program Brumle, at
    // 96 kHz) peaks at 2.494 in the prototype's units, so 0.2 puts it at 0.499: -6.0 dBFS, under
    // the limiter's 0.6.
    static constexpr float kLevel = 0.2f;

    // The keyboard set as plain values, read once per block.
    void readKeyboardSet()
    {
        for (int i = 0; i < kNumParams; ++i) keyView_.v[i] = get(BRUMLE_KEYBOARD_SET, i);
    }

    void handleMidi(const MidiEvent& ev)
    {
        const bool keyboard = mode() == BRUMLE_MODE_KEYBOARD;
        if (ev.isNoteOn()) { if (keyboard) noteOn(ev.data1, ev.data2 / 127.0f); }
        else if (ev.isNoteOff()) { if (keyboard) noteOff(ev.data1); }
        else if (ev.isAllNotesOff()) { for (Voice& v : voices_) if (v.active) v.choke(v.knob(kDamp)); }
    }

    void noteOn(int note, float velocity)
    {
        // One voice per note number: the same note again chokes its own ring, each with its Damp.
        for (Voice& v : voices_) if (v.active && v.note == note) v.choke(v.knob(kDamp));
        Voice* slot = nullptr;
        for (Voice& v : voices_) if (!v.active) { slot = &v; break; }
        if (!slot) slot = &voices_[0];          // the prototype's rule; Task 6 steals the quietest
        float dir = 1.0f;                        // Out
        const int stroke = (int)std::lround(keyView_.v[kStroke]);
        if (stroke == kStrokeIn) dir = -1.0f;
        else if (stroke == kStrokeAlternate) { lastDir_[note] = -lastDir_[note]; dir = (float)lastDir_[note]; }
        slot->start(note, velocity, keyView_, dir, rng_, internalRate_);
        slot->followsKeyboard = true;
        lastNote_.store(note, std::memory_order_relaxed);
    }

    void noteOff(int note)
    {
        for (Voice& v : voices_)
            if (v.active && v.note == note && (int)std::lround(v.knob(kKeyUp)) == kKeyUpDamp) v.choke(v.knob(kDamp));
    }

    // The peaks are left alone up to 0.6 and bent towards 1 above it (Didgeridoo's limiter).
    static float limit(float y)
    {
        const float size = std::fabs(y);
        if (size <= 0.6f) return y;
        const float bent = 0.6f + 0.4f * fastTanh((size - 0.6f) * 2.5f);
        return y < 0.0f ? -bent : bent;
    }

    struct Dc { float x1 = 0, y1 = 0; };

    // One channel of the bus: DC blocker, level, limiter. Values too small to hear are flushed to
    // zero, the blocker's memory included, so that silence is exact and no denormal tail lingers.
    float bus(Dc& dc, float x) const
    {
        const float y = x - dc.x1 + dcCoeff_ * dc.y1;
        dc.x1 = x;
        dc.y1 = std::fabs(y) < 1e-20f ? 0.0f : y;
        const float out = limit(y * kLevel);
        return std::fabs(out) < 1e-20f ? 0.0f : out;
    }

    void render(float* outL, float* outR, int from, int to)
    {
        for (int i = from; i < to; ++i)
        {
            float l = 0.0f, r = 0.0f;
            for (Voice& v : voices_)
            {
                if (!v.active) continue;
                if (v.followsKeyboard && v.controlDue()) v.view = keyView_;   // a keyboard voice follows the knobs
                const StereoSample s = v.process();
                l += s.l; r += s.r;
            }
            const float yl = bus(dcL_, l), yr = bus(dcR_, r);
            outL[i] = yl;
            if (outR) outR[i] = yr;
        }
    }

    // --- knob sets and cross-thread state --------------------------------------------------
    std::atomic<float> sets_[BRUMLE_NUM_SETS][kNumParams];   // normalised
    std::atomic<int>   program_[BRUMLE_NUM_SETS] = {};
    std::atomic<int>   mode_{BRUMLE_MODE_KEYBOARD};
    std::atomic<int>   padNote_[BRUMLE_NUM_PADS];
    std::atomic<int>   padGroup_[BRUMLE_NUM_PADS];
    std::atomic<int>   lastNote_{-1};
    std::atomic<int>   sounding_{0};
    std::atomic<bool>  resetPending_{false};

    MidiQueue posted_;
    MidiEvent events_[kMaxEvents];
    int       numEvents_ = 0;

    // --- audio thread ----------------------------------------------------------------------
    double hostRate_ = 44100.0, internalRate_ = 44100.0;
    float  dcCoeff_ = 0.9995f;
    KnobView keyView_{};
    Voice  voices_[kNumSlots];
    std::mt19937 rng_{12345};
    int    lastDir_[128];
    Dc     dcL_, dcR_;
};

// ---------------------------------------------------------------------------------------------
// C interface: the tables
// ---------------------------------------------------------------------------------------------
int brumle_num_params(void) { return kNumParams; }

void brumle_param_info(int index, BrumleParamInfo* out)
{
    if (!out) return;
    *out = BrumleParamInfo{};
    if (!validParam(index)) return;
    const Param& p = param(index);
    out->identifier = p.id; out->name = p.name; out->unit = p.unit; out->kind = p.kind;
    out->minValue = p.min; out->maxValue = p.max; out->defaultValue = p.def;
    out->logarithmic = p.logarithmic ? 1 : 0;
    out->numChoices = p.kind == BRUMLE_KIND_CHOICE ? (int)p.max + 1 : 0;
    out->section = sectionOf(index);
}

const char* brumle_param_choice(int index, int choice) { return validParam(index) ? choiceName(index, choice) : ""; }

float brumle_param_to_plain(int index, float normalised) { return validParam(index) ? param(index).toPlain(normalised) : 0.0f; }
float brumle_param_to_normalised(int index, float plain) { return validParam(index) ? param(index).toNormalised(plain) : 0.0f; }

const char* brumle_param_display(int index, float plain, char* buffer, int bufferSize)
{
    if (!buffer || bufferSize <= 0) return "";
    buffer[0] = 0;
    if (!validParam(index)) return buffer;
    const Param& p = param(index);
    if (index == kOctave && plain >= 0.5f) std::snprintf(buffer, (size_t)bufferSize, "+%d", (int)std::lround(plain));
    else if (p.kind == BRUMLE_KIND_CHOICE) std::snprintf(buffer, (size_t)bufferSize, "%s", choiceName(index, (int)std::lround(plain)));
    else if (p.kind == BRUMLE_KIND_INT) std::snprintf(buffer, (size_t)bufferSize, "%d", (int)std::lround(plain));
    else
    {
        // A frequency has two decimals only where it is small: "6.00 Hz", "800 Hz".
        const int decimals = p.decimals >= 0 ? p.decimals : (std::fabs(plain) < 10.0f ? 2 : 0);
        std::snprintf(buffer, (size_t)bufferSize, "%.*f", decimals, (double)plain);
        if (buffer[0] == '-')     // turn "-0.0" into "0.0"
        {
            bool allZero = true;
            for (const char* q = buffer + 1; *q; ++q) if (*q != '0' && *q != '.') { allZero = false; break; }
            if (allZero) std::memmove(buffer, buffer + 1, std::strlen(buffer));
        }
    }
    return buffer;
}

static bool validSection(int s) { return s >= 0 && s < (int)sections().size(); }

int brumle_num_sections(void) { return (int)sections().size(); }
const char* brumle_section_name(int s) { return validSection(s) ? sections()[(size_t)s].name : ""; }
int brumle_section_size(int s) { return validSection(s) ? (int)sections()[(size_t)s].params.size() : 0; }
int brumle_section_param(int s, int pos)
{
    return pos >= 0 && pos < brumle_section_size(s) ? sections()[(size_t)s].params[(size_t)pos] : -1;
}

int brumle_num_lfos(void) { return kNumLfos; }
int brumle_lfo_amount(int lfo, int param) { return lfo >= 0 && lfo < kNumLfos && validParam(param) ? amountOf(lfo, param) : -1; }
int brumle_vel_amount(int param) { return validParam(param) ? velAmountOf(param) : -1; }

int brumle_num_programs(void) { return (int)programs().size(); }
const char* brumle_program_name(int p) { return p >= 0 && p < brumle_num_programs() ? programs()[(size_t)p].name : ""; }
int brumle_program_sets(int param) { return validParam(param) && programSets(param) ? 1 : 0; }
float brumle_program_value(int p, int param)
{
    return p >= 0 && p < brumle_num_programs() && validParam(param) ? programs()[(size_t)p].values[param] : 0.0f;
}

// ---------------------------------------------------------------------------------------------
// C interface: the engine. Every call tolerates a null engine and indices out of range.
// ---------------------------------------------------------------------------------------------
BrumleEngine* brumle_create(void) { return new BrumleEngine(); }
void brumle_destroy(BrumleEngine* e) { delete e; }
void brumle_prepare(BrumleEngine* e, double sampleRate) { if (e) e->prepare(sampleRate); }
void brumle_reset(BrumleEngine* e) { if (e) e->reset(); }
void brumle_request_reset(BrumleEngine* e) { if (e) e->requestReset(); }
int  brumle_latency(const BrumleEngine*) { return 0; }      // no oversampling yet (Task 6)

float brumle_get_plain(const BrumleEngine* e, int set, int index)
{
    return e && validSet(set) && validParam(index) ? e->get(set, index) : 0.0f;
}
float brumle_get_normalised(const BrumleEngine* e, int set, int index)
{
    return e && validSet(set) && validParam(index) ? e->getNormalised(set, index) : 0.0f;
}
void brumle_set_plain(BrumleEngine* e, int set, int index, float plain)
{
    if (e && validSet(set) && validParam(index)) e->set(set, index, plain);
}
void brumle_set_normalised(BrumleEngine* e, int set, int index, float n)
{
    if (e && validSet(set) && validParam(index)) e->setNormalised(set, index, n);
}
void brumle_set_program(BrumleEngine* e, int set, int program) { if (e && validSet(set)) e->setProgram(set, program); }
int  brumle_get_program(const BrumleEngine* e, int set) { return e && validSet(set) ? e->program(set) : 0; }
void brumle_set_mode(BrumleEngine* e, int mode) { if (e) e->setMode(mode); }
int  brumle_get_mode(const BrumleEngine* e) { return e ? e->mode() : BRUMLE_MODE_KEYBOARD; }

int  brumle_pad_note(const BrumleEngine* e, int pad) { return e && validPad(pad) ? e->padNote(pad) : -1; }
void brumle_set_pad_note(BrumleEngine* e, int pad, int note) { if (e && validPad(pad)) e->setPadNote(pad, note); }
int  brumle_pad_group(const BrumleEngine* e, int pad) { return e && validPad(pad) ? e->padGroup(pad) : 0; }
void brumle_set_pad_group(BrumleEngine* e, int pad, int group) { if (e && validPad(pad)) e->setPadGroup(pad, group); }
int  brumle_last_note(const BrumleEngine* e) { return e ? e->lastNote() : -1; }
void brumle_send_to_pad(BrumleEngine* e, int pad) { if (!e || !validPad(pad)) return; }   // Task 5
void brumle_load_default_kit(BrumleEngine* e) { if (!e) return; }                         // Task 5
int  brumle_sounding_voices(const BrumleEngine* e) { return e ? e->soundingVoices() : 0; }

void brumle_post_midi(BrumleEngine* e, int status, int data1, int data2, int sampleOffset)
{
    if (e) e->postMidi((uint8_t)status, (uint8_t)(data1 & 0x7F), (uint8_t)(data2 & 0x7F), sampleOffset);
}

void brumle_midi(BrumleEngine* e, int status, int data1, int data2, int sampleOffset)
{
    if (e) e->midi((uint8_t)status, (uint8_t)(data1 & 0x7F), (uint8_t)(data2 & 0x7F), sampleOffset);
}

void brumle_process(BrumleEngine* e, float* left, float* right, int frames)
{
    if (!left || frames <= 0) return;
    if (e) { e->process(left, right, frames); return; }
    std::memset(left, 0, sizeof(float) * (size_t)frames);
    if (right) std::memset(right, 0, sizeof(float) * (size_t)frames);
}
