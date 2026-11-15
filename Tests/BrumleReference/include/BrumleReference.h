// The listening prototype (.planning/research/spike/brumle_spike.cpp) as a test reference.
// It runs at a fixed 96 kHz. Units are the prototype's own: fractions, not percent.
#ifndef BRUMLE_REFERENCE_H
#define BRUMLE_REFERENCE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct BrumleRefParams {
    float ring, edge, offset, bodyDb, buzz, clang, velsens; int stroke;
    float damp, vary, vowel, sweep, sweeptime; int curve; float reso, throatDb, throattune,
    open, close, breath, puff, pufftime, air; int levelOnlyVelocity;
} BrumleRefParams;

typedef struct BrumleRefEvent { double time; int note; float velocity; int params; int chokeOnly; } BrumleRefEvent;

void brumle_ref_default_params(BrumleRefParams* out);

// Renders `frames` mono samples at 96 kHz: events sorted by time, `params` indexes `paramSets`.
void brumle_ref_render(const BrumleRefEvent* events, int numEvents,
                       const BrumleRefParams* paramSets, int numParamSets, float* out, int frames);

#ifdef __cplusplus
}
#endif

#endif
