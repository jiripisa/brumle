// Params.h - the parameter table of the Brumle engine: the knobs, the amounts, the sections and
// the programs.
//
// The identifiers and the order are permanent from here on: only ever append.

#pragma once

#include "BrumleDSP.h"

#include <algorithm>
#include <cmath>
#include <vector>

namespace brumle {

// ---------------------------------------------------------------------------------------------
// The knobs, group by group. One set of them is a sound; the keyboard has one and every pad has
// one.
// ---------------------------------------------------------------------------------------------
enum Params
{
    // Reed
    kRing,          // s     how long the tongue rings after a pluck
    kEdge,          // -     how sharply the tongue's tip strikes the frame: the harmonics' reach
    kOffset,        // -     how far the tongue sits off the middle of the gap: the even harmonics
    kBody,          // dB    the level of the reed's own body tone under the twang
    kBuzz,          // %     the rattle of the tongue against the frame
    kClang,         // %     the metallic clang of a hard pluck
    // Stroke
    kVelSens,       // %     how much the velocity changes the loudness
    kStroke,        // -     the direction of the pluck: out, in, or one after the other
    kDamp,          // ms    how fast a finger stops the tongue
    kKeyUp,         // -     what a released key does: let the tongue ring or stop it
    kVary,          // %     the random difference between one pluck and the next
    // Mouth
    kVowel,         // Hz    the formant of the mouth cavity the harmonics pass through
    kSweep,         // st    how far the mouth moves the vowel after a pluck
    kSweepTime,     // ms    how long that movement takes
    kCurve,         // -     the path of that movement
    kReso,          // -     how sharply the mouth cavity resonates
    kThroat,        // dB    the level of the throat's resonance
    kThroatTune,    // Hz    where the throat's resonance stands
    kOpen,          // %     how open the lips are: the brightness of the mouth
    kClose,         // %     how far the lips are closed
    // Breath
    kBreath,        // %     the breath through the instrument (negative: drawn in)
    kPuff,          // %     the burst of breath that goes with a pluck
    kPuffTime,      // ms    how long that burst lasts
    kAir,           // %     the hiss of air in the gap
    // Master
    kVolume,        // dB
    kPan,           // %
    kTune,          // ct    fine tuning
    kOctave,        // -     the octave of the keyboard
    kBendVowel,     // st    how far the pitch bend moves the vowel
    kLfoStart,      // -     whether an LFO restarts with every hit or runs free
    kLfo1Rate,      // Hz
    kLfo1Shape,     // -
    kLfo2Rate,      // Hz
    kLfo2Shape,     // -
    kNumKnobs,
    // After the knobs come the amounts: first the LFOs' (amountOf), then the velocity's
    // (velAmountOf). An amount says how far that source moves that knob, as a part of the
    // knob's travel.
    kNumLfoAmounts = 22,
    kNumVelAmounts = 25,
    kNumParams = kNumKnobs + kNumLfoAmounts + kNumVelAmounts
};

constexpr int kNumLfos = 2;

// The knobs an LFO can move: the continuous ones the mouth, the breath and the reed answer to.
constexpr int kLfoTargets[] = { kVowel, kClose, kBreath, kOpen, kReso, kThroat, kBuzz, kBody, kVolume, kEdge, kOffset };
constexpr int kNumLfoTargets = (int)(sizeof(kLfoTargets) / sizeof(kLfoTargets[0]));

// The knobs the hit's velocity can move: the same, and the times, the pitch and the LFOs' rates.
constexpr int kVelTargets[] = { kRing, kDamp, kEdge, kOffset, kBody, kBuzz, kClang, kVary, kVowel, kSweep, kSweepTime,
                                kReso, kThroat, kThroatTune, kOpen, kClose, kBreath, kPuff, kPuffTime, kAir, kVolume,
                                kPan, kTune, kLfo1Rate, kLfo2Rate };
constexpr int kNumVelTargets = (int)(sizeof(kVelTargets) / sizeof(kVelTargets[0]));

static_assert(kNumLfoAmounts == kNumLfos * kNumLfoTargets, "the LFO amounts do not fill the table");
static_assert(kNumVelAmounts == kNumVelTargets, "the velocity amounts do not fill the table");

// The parameter that says how far LFO `lfo` moves `knob`; -1 when it cannot move it.
constexpr int amountOf(int lfo, int knob)
{
    for (int t = 0; t < kNumLfoTargets; ++t) if (kLfoTargets[t] == knob) return kNumKnobs + lfo * kNumLfoTargets + t;
    return -1;
}

// The parameter that says how far the velocity moves `knob`; -1 when it cannot move it.
constexpr int velAmountOf(int knob)
{
    for (int t = 0; t < kNumVelTargets; ++t) if (kVelTargets[t] == knob) return kNumKnobs + kNumLfoAmounts + t;
    return -1;
}

// The shapes of an LFO's cycle. Steps takes a new random level each cycle and holds it; Wander
// takes one and moves there smoothly.
enum LfoShape { kLfoSine, kLfoTriangle, kLfoRampUp, kLfoRampDown, kLfoSquare, kLfoSteps, kLfoWander, kNumLfoShapes };
enum Stroke { kStrokeOut, kStrokeIn, kStrokeAlternate, kNumStrokes };
enum KeyUp { kKeyUpRing, kKeyUpDamp, kNumKeyUps };
enum Curve { kCurveGlide, kCurveLine, kCurveThereAndBack, kCurveStep, kNumCurves };
enum LfoStart { kLfoStartHit, kLfoStartFree, kNumLfoStarts };

struct Param
{
    const char* id;
    const char* name;
    const char* unit;
    int   kind;                 // BRUMLE_KIND_*
    float min, max, def;
    bool  logarithmic;
    int   decimals;             // for the text of a float; -1 = by size, as a frequency is written

    float toPlain(float norm) const
    {
        norm = std::clamp(norm, 0.0f, 1.0f);
        if (kind == BRUMLE_KIND_CHOICE)
        {
            const int n = (int)max + 1;
            return n < 2 ? 0.0f : (float)std::clamp((int)std::lround(norm * (float)(n - 1)), 0, n - 1);
        }
        if (kind == BRUMLE_KIND_INT) return std::round(min + norm * (max - min));
        if (logarithmic && min > 0.0f && max > 0.0f) return min * std::pow(max / min, norm);
        return min + (max - min) * norm;
    }

    float toNormalised(float plain) const
    {
        if (kind == BRUMLE_KIND_CHOICE)
        {
            const int n = (int)max + 1;
            return n < 2 ? 0.0f : std::clamp(plain / (float)(n - 1), 0.0f, 1.0f);
        }
        if (max == min) return 0.0f;
        plain = std::clamp(plain, std::fmin(min, max), std::fmax(min, max));
        if (kind == BRUMLE_KIND_FLOAT && logarithmic && min > 0.0f && max > 0.0f)
            return std::clamp(std::log(plain / min) / std::log(max / min), 0.0f, 1.0f);
        return std::clamp((plain - min) / (max - min), 0.0f, 1.0f);
    }
};

// The whole table: the knobs, the LFO amounts ("lfo1vowel", "LFO 1>Vowel"), then the velocity
// amounts ("velring", "VEL>Ring").
const Param& param(int index);
inline bool validParam(int i) { return i >= 0 && i < kNumParams; }

const char* choiceName(int index, int choice);

struct Section { const char* name; std::vector<int> params; };
const std::vector<Section>& sections();
int sectionOf(int param);

// Built-in programs: the defaults with a few values overridden.
struct Program { const char* name; float values[kNumParams]; };
const std::vector<Program>& programs();
bool programSets(int param);     // false for the knobs a program leaves alone

} // namespace brumle
