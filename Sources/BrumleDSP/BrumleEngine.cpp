// BrumleEngine.cpp - the Brumle sound engine and its C interface.
//
// One engine is a pool of voices (Voice.h), each a plucked reed, and seventeen knob sets: the
// keyboard's and one per pad. At most 16 voices sound at once: a hit that would be the 17th
// steals the quietest, which fades out in 3 ms.
//   * In keyboard mode every note plays the keyboard set at its own pitch, one voice per note
//     number: the same note again chokes its own ring and plucks anew. The voice follows the
//     keyboard set while it rings.
//   * In pad mode notes 36-51 hit pads 1-16. A pad hit is a key press frozen: its voice copies
//     the pad's set at the hit and sounds at the pad's note. It chokes the voices of its own pad
//     and, unless its group is Off, of every pad in its group.
//
//   voices -> sum (L, R) -> DC blocker -> kLevel -> [half-band decimator] -> limiter -> out
//
// Below 88.2 kHz everything up to kLevel runs at twice the host rate (the internal rate), and
// a half-band filter (HalfBand.h) decimates it: the reed's bright bursts would otherwise fold
// back into the band. From 88.2 kHz up the internal rate is the host's and there is no filter.
// The limiter always runs at the host rate.
//
// What a voice plays is its view (viewFor): the knob set, moved by the voice's two LFOs, the
// hit's velocity and, for a keyboard voice, the wheels.

// A product and a sum stay two roundings. An optimised build would otherwise fuse them into one
// multiply-add where a debug build does not, and the two builds would render different last
// bits: the engine's sound must be the same in both, and the same as the references it is
// tested against.
#pragma clang fp contract(off)

#include "BrumleDSP.h"
#include "HalfBand.h"
#include "MidiQueue.h"
#include "Params.h"
#include "Voice.h"

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <random>

using namespace brumle;

namespace {

bool validSet(int set) { return set >= 0 && set < BRUMLE_NUM_SETS; }

static_assert(kLfo2Rate == kLfo1Rate + 2 && kLfo2Shape == kLfo1Shape + 2, "an LFO's knobs are two apart");

// For every knob, the amounts that move it (-1 where a source cannot), and the knobs that
// anything can move: an LFO, the velocity or a wheel.
struct Moves
{
    int lfo[kNumKnobs][kNumLfos];
    int vel[kNumKnobs];
    int knobs[kNumKnobs];
    int numKnobs;
};

constexpr Moves makeMoves()
{
    Moves m{};
    for (int i = 0; i < kNumKnobs; ++i)
    {
        bool moves = i == kClose || i == kBreath;      // the mod wheel and the aftertouch
        for (int k = 0; k < kNumLfos; ++k) { m.lfo[i][k] = amountOf(k, i); moves = moves || m.lfo[i][k] >= 0; }
        m.vel[i] = velAmountOf(i);
        moves = moves || m.vel[i] >= 0;
        if (moves) m.knobs[m.numKnobs++] = i;
    }
    return m;
}

constexpr Moves kMoves = makeMoves();

// The seeds of the LFOs' generators: a voice's at every hit with LFO Start = Hit, the engine's
// free-running ones at every reset.
constexpr uint32_t kHitSeed = 0x9E3779B9u, kFreeSeed = 0x2F6E2B11u;
bool validPad(int pad) { return pad >= 0 && pad < BRUMLE_NUM_PADS; }
int  padSet(int pad) { return pad + 1; }

// The note Send to pad gives a pad when no note has been played: C2.
constexpr int kSendNoteIfNone = 36;

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
        loadDefaultKit();
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

    // Send to pad: the keyboard set and its program go to the pad's set, the last note played to
    // the pad's note. The group stays.
    void sendToPad(int pad)
    {
        const int set = padSet(pad);
        for (int i = 0; i < kNumParams; ++i) sets_[set][i].store(getNormalised(BRUMLE_KEYBOARD_SET, i), std::memory_order_relaxed);
        program_[set].store(program(BRUMLE_KEYBOARD_SET), std::memory_order_relaxed);
        const int last = lastNote();
        padNote_[pad].store(last >= 0 ? last : kSendNoteIfNone, std::memory_order_relaxed);
    }

    void loadDefaultKit()
    {
        for (int pad = 0; pad < BRUMLE_NUM_PADS; ++pad)
        {
            const KitPad& k = kDefaultKit[(size_t)pad];
            const int s = padSet(pad);
            setProgram(s, k.program);
            set(s, kOctave, param(kOctave).def);             // a program leaves the octave alone
            for (const Override& o : k.overrides) if (validParam(o.param)) set(s, o.param, o.value);
            setPadNote(pad, k.note);
            setPadGroup(pad, k.group);
        }
    }

    int lastNote() const { return lastNote_.load(std::memory_order_relaxed); }
    int soundingVoices() const { return sounding_.load(std::memory_order_relaxed); }
    int latency() const { return latency_.load(std::memory_order_relaxed); }

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
        oversampling_ = sampleRate < kOversampleBelow ? 2 : 1;
        internalRate_ = sampleRate * oversampling_;
        dcCoeff_ = (float)(1.0 - 48.0 / internalRate_);    // 0.9995 at 96 kHz, the prototype's
        decimL_.design();
        decimR_.design();
        latency_.store(oversampling_ == 2 ? HalfBand::kLatency : 0, std::memory_order_relaxed);
        reset();
    }

    void reset()
    {
        for (Voice& v : voices_) v = Voice();
        rng_.seed(12345);
        for (int& d : lastDir_) d = -1;
        for (int& d : padDir_) d = -1;
        lastNote_.store(-1, std::memory_order_relaxed);
        dcL_ = dcR_ = Dc{};
        decimL_.reset();
        decimR_.reset();
        for (int k = 0; k < kNumLfos; ++k) freeLfo_[k].restart(kFreeSeed + (uint32_t)k);
        freeTick_ = 0;
        bend_ = modWheel_ = pressure_ = 0.0f;
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
    // At most BRUMLE_MAX_VOICES sound; the other slots let the voices being choked fade out. 40
    // leave room for 16 voices choked at once while 16 new ones start (all pads hit together),
    // so that a choked voice is cut only when even that is not enough.
    static constexpr int kNumSlots = 40;
    static_assert(kNumSlots > BRUMLE_MAX_VOICES, "room for the voices being choked");
    static constexpr int kMaxEvents = 256;

    // A stolen voice falls 40 dB in this long.
    static constexpr float kStealMs = 3.0f;

    // Below this host rate the voices run at twice it.
    static constexpr double kOversampleBelow = 88200.0;

    // The output scale. The default hit at full velocity (C2, velocity 127, program Brumle, at
    // 96 kHz) peaks at 2.494 in the prototype's units, so 0.2 puts it at 0.499: -6.0 dBFS, under
    // the limiter's 0.6.
    static constexpr float kLevel = 0.2f;

    // The keyboard set, normalised and as plain values, read once per block.
    void readKeyboardSet()
    {
        for (int i = 0; i < kNumParams; ++i)
        {
            keyNorm_[i] = getNormalised(BRUMLE_KEYBOARD_SET, i);
            keyView_.v[i] = param(i).toPlain(keyNorm_[i]);
        }
    }

    // Where every knob of `v` stands now. A knob a source moves stands at
    //   knob + sum of (LFO amount * LFO value) - VEL amount * (1 - velocity)  (+ a wheel),
    // in parts of its travel and no further than its ends; Volume's VEL amount is a gain
    // instead, and the pitch bend multiplies the Vowel. The one place that adds modulation:
    // with every amount and wheel at rest, the view is the knob set itself, value for value.
    void viewFor(const Voice& v, KnobView& out) const
    {
        const bool keyboard = v.followsKeyboard();
        const float* set = keyboard ? keyNorm_ : v.setAtHit;
        const float* plain = keyboard ? keyView_.v : v.plainAtHit;
        std::copy(plain, plain + kNumParams, out.v);

        float lfoValue[kNumLfos];
        for (int k = 0; k < kNumLfos; ++k)
            lfoValue[k] = v.lfo[k].value(std::clamp((int)std::lround(out.v[kLfo1Shape + 2 * k]), 0, (int)kNumLfoShapes - 1));
        const float soft = 1.0f - v.vel;

        for (int n = 0; n < kMoves.numKnobs; ++n)
        {
            const int i = kMoves.knobs[n];
            float position = set[i];
            bool moved = false;
            for (int k = 0; k < kNumLfos; ++k)
            {
                const int slot = kMoves.lfo[i][k];
                const float amount = slot >= 0 ? out.v[slot] / 100.0f : 0.0f;
                if (amount != 0.0f) { position += amount * lfoValue[k]; moved = true; }
            }
            const float velAmount = kMoves.vel[i] >= 0 && i != kVolume ? out.v[kMoves.vel[i]] / 100.0f : 0.0f;
            if (velAmount != 0.0f) { position -= velAmount * soft; moved = true; }
            if (keyboard)
            {
                if (i == kClose && modWheel_ != 0.0f) { position += modWheel_; moved = true; }
                if (i == kBreath && pressure_ != 0.0f) { position += 0.5f * pressure_; moved = true; }
            }
            if (moved) out.v[i] = param(i).toPlain(std::clamp(position, 0.0f, 1.0f));
        }

        out.velocityGain = std::max(0.0f, 1.0f - out.v[velAmountOf(kVolume)] / 100.0f * soft);
        if (keyboard && bend_ != 0.0f) out.v[kVowel] *= std::pow(2.0f, bend_ * out.v[kBendVowel] / 12.0f);
    }

    // A hit's LFOs: restarted (Hit), or where the engine's free-running ones stand (Free).
    void startLfos(Voice& v, int start) const
    {
        for (int k = 0; k < kNumLfos; ++k)
        {
            if (start == kLfoStartFree) v.lfo[k] = freeLfo_[k];
            else v.lfo[k].restart(kHitSeed + (uint32_t)k);
        }
    }

    // The free-running LFOs go round at the keyboard set's rates, one control tick at a time.
    void turnFreeLfos()
    {
        for (int k = 0; k < kNumLfos; ++k)
            freeLfo_[k].advance(keyView_.v[kLfo1Rate + 2 * k] * 16.0f / (float)internalRate_);
    }

    void handleMidi(const MidiEvent& ev)
    {
        if (ev.isNoteOn())
        {
            const float velocity = ev.data2 / 127.0f;
            if (mode() == BRUMLE_MODE_KEYBOARD) noteOn(ev.data1, velocity);
            else if (validPad(ev.data1 - BRUMLE_FIRST_PAD_NOTE)) padHit(ev.data1 - BRUMLE_FIRST_PAD_NOTE, ev.data1, velocity);
        }
        else if (ev.isNoteOff()) noteOff(ev.data1);
        else if (ev.isAllNotesOff()) { for (Voice& v : voices_) if (v.active) v.choke(v.knob(kDamp)); }
        else if (ev.isController() && ev.data1 == 121) bend_ = modWheel_ = pressure_ = 0.0f;   // Reset All Controllers
        else if (ev.isController() && ev.data1 == 1) modWheel_ = ev.data2 / 127.0f;
        else if (ev.isAftertouch()) pressure_ = ev.data1 / 127.0f;
        else if (ev.isPitchBend())          // -1 at the bottom, +1 at the top
        {
            const int bend = ev.pitchBend();
            bend_ = (float)bend / (bend >= 0 ? 8191.0f : 8192.0f);
        }
    }

    // Before a hit: if BRUMLE_MAX_VOICES voices sound, the quietest of them is choked, in
    // kStealMs. The hit's own chokes (its note, its pad, its group) have been done by then, so a
    // voice is stolen only when they left no room.
    void makeRoom()
    {
        int sounding = 0;
        Voice* quietest = nullptr;
        float least = 0.0f;
        for (Voice& v : voices_)
        {
            if (!v.active || v.choking) continue;
            ++sounding;
            const float loudness = v.loudness();
            if (!quietest || loudness < least) { quietest = &v; least = loudness; }
        }
        if (sounding >= BRUMLE_MAX_VOICES) quietest->choke(kStealMs);
    }

    // The slot a hit takes: a free one, or else the quietest of those being choked, which is cut.
    // After makeRoom at most BRUMLE_MAX_VOICES - 1 voices sound, so one of the two is there.
    Voice& freeSlot()
    {
        Voice* quietest = nullptr;
        float least = 0.0f;
        for (Voice& v : voices_)
        {
            if (!v.active) return v;
            if (!v.choking) continue;
            const float loudness = v.loudness();
            if (!quietest || loudness < least) { quietest = &v; least = loudness; }
        }
        return quietest ? *quietest : voices_[0];
    }

    // The direction of a stroke: Out, In, or the other way from the last stroke `last` made.
    static float direction(int stroke, int& last)
    {
        if (stroke == kStrokeIn) return -1.0f;
        if (stroke != kStrokeAlternate) return 1.0f;
        last = -last;
        return (float)last;
    }

    // What is taken at the hit is taken from the hit's view: its velocity moves Ring and Tune.
    void pluck(Voice& v, const float* plain, float dir)
    {
        startLfos(v, (int)std::lround(plain[kLfoStart]));
        viewFor(v, v.view);
        v.start(dir, rng_, internalRate_);
    }

    void noteOn(int note, float velocity)
    {
        // One voice per note number: the same note again chokes its own ring, each with its Damp.
        for (Voice& v : voices_)
            if (v.active && v.origin.kind == kOriginKey && v.origin.note == note) v.choke(v.knob(kDamp));
        makeRoom();
        Voice& slot = freeSlot();
        const float dir = direction((int)std::lround(keyView_.v[kStroke]), lastDir_[note]);
        slot.take(Origin{ kOriginKey, note, -1, 0 }, note, velocity);
        pluck(slot, keyView_.v, dir);
        lastNote_.store(note, std::memory_order_relaxed);
    }

    // A pad hit chokes its own pad's voices and, unless its group is Off, every pad voice of its
    // group, each with its Damp. Stroke Alternate alternates per group, or per pad with no group.
    void padHit(int pad, int note, float velocity)
    {
        const int group = padGroup(pad);
        for (Voice& v : voices_)
            if (v.active && v.origin.kind == kOriginPad && (v.origin.pad == pad || (group != 0 && v.origin.group == group)))
                v.choke(v.knob(kDamp));
        makeRoom();
        Voice& slot = freeSlot();
        slot.take(Origin{ kOriginPad, note, pad, group }, padNote(pad), velocity);
        const int set = padSet(pad);
        for (int i = 0; i < kNumParams; ++i)        // the pad's set, frozen at the hit
        {
            slot.setAtHit[i] = getNormalised(set, i);
            slot.plainAtHit[i] = param(i).toPlain(slot.setAtHit[i]);
        }
        int& last = group != 0 ? padDir_[group - 1] : padDir_[BRUMLE_NUM_GROUPS + pad];
        pluck(slot, slot.plainAtHit, direction((int)std::lround(slot.plainAtHit[kStroke]), last));
    }

    // A released key stops the voices it started whose Key Up is Damp: a key's, or a pad's.
    void noteOff(int note)
    {
        for (Voice& v : voices_)
            if (v.active && v.origin.note == note && (int)std::lround(v.knob(kKeyUp)) == kKeyUpDamp) v.choke(v.knob(kDamp));
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

    // One channel of the bus at the internal rate: DC blocker and level. The blocker's memory is
    // flushed to zero when it is too small to hear, so that silence is exact and no denormal
    // tail lingers.
    float bus(Dc& dc, float x) const
    {
        const float y = x - dc.x1 + dcCoeff_ * dc.y1;
        dc.x1 = x;
        dc.y1 = std::fabs(y) < 1e-20f ? 0.0f : y;
        return y * kLevel;
    }

    // The bus at the host rate: the limiter, and the same flush.
    static float limited(float y)
    {
        const float out = limit(y);
        return std::fabs(out) < 1e-20f ? 0.0f : out;
    }

    // One internal sample: the voices, summed, through the bus.
    StereoSample tick()
    {
        if (freeTick_-- <= 0) { turnFreeLfos(); freeTick_ = 15; }
        float l = 0.0f, r = 0.0f;
        for (Voice& v : voices_)
        {
            if (!v.active) continue;
            if (v.controlDue()) { viewFor(v, v.view); v.turnLfos(); }   // the knobs as this tick sees them
            const StereoSample s = v.process();
            l += s.l; r += s.r;
        }
        return { bus(dcL_, l), bus(dcR_, r) };
    }

    // Host frames [from, to): one internal sample each, or two decimated into one.
    void render(float* outL, float* outR, int from, int to)
    {
        for (int i = from; i < to; ++i)
        {
            StereoSample y = tick();
            if (oversampling_ == 2)
            {
                const StereoSample second = tick();
                y = { decimL_.process(y.l, second.l), decimR_.process(y.r, second.r) };
            }
            outL[i] = limited(y.l);
            if (outR) outR[i] = limited(y.r);
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
    std::atomic<int>   latency_{0};
    std::atomic<bool>  resetPending_{false};

    MidiQueue posted_;
    MidiEvent events_[kMaxEvents];
    int       numEvents_ = 0;

    // --- audio thread ----------------------------------------------------------------------
    double internalRate_ = 88200.0;
    int    oversampling_ = 2;                                 // internal samples per host frame
    float  dcCoeff_ = 0.9995f;
    float  keyNorm_[kNumParams] = {};
    KnobView keyView_{};
    Lfo    freeLfo_[kNumLfos];
    int    freeTick_ = 0;
    float  bend_ = 0.0f, modWheel_ = 0.0f, pressure_ = 0.0f;   // -1..1, 0..1, 0..1
    Voice  voices_[kNumSlots];
    std::mt19937 rng_{12345};
    int    lastDir_[128];                                     // per keyboard note
    int    padDir_[BRUMLE_NUM_GROUPS + BRUMLE_NUM_PADS];       // per group 1-16, then per pad with no group
    Dc     dcL_, dcR_;
    HalfBand decimL_, decimR_;
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
int  brumle_latency(const BrumleEngine* e) { return e ? e->latency() : 0; }

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
void brumle_send_to_pad(BrumleEngine* e, int pad) { if (e && validPad(pad)) e->sendToPad(pad); }
void brumle_load_default_kit(BrumleEngine* e) { if (e) e->loadDefaultKit(); }
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
