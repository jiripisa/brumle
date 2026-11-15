// HalfBand.h - the decimator by 2 that brings the voices' doubled rate back to the host's.
//
// Below 88.2 kHz the voices run at twice the host rate (BrumleEngine.cpp), so that the reed's
// bright bursts have room above the host's Nyquist instead of folding back into the band. This
// filter takes that room away again: a linear-phase FIR half-band low-pass, a windowed sinc with
// a Kaiser window, of which every second output is kept.
//
// A half-band filter's taps are zero at every even distance from the centre but the centre
// itself, which is 1/2: only the centre and the taps at odd distances are stored and multiplied,
// and the symmetry halves those again. The response is 1/2 (-6 dB) at the host's Nyquist and
// mirrors about it: the passband falls as the stopband rises.
//
// The taps are designed in prepare (design()), not in the audio thread; process() neither
// allocates nor branches on the signal.

#pragma once

#include <cmath>

namespace brumle {

class HalfBand
{
public:
    // The length. The centre lies kCentre input samples in; it is odd, so the outermost taps
    // are not zero.
    //
    // Measured (the response of these taps, in parts of the host rate fs): flat within 0.0003 dB
    // up to 0.40 fs (17.6 kHz at 44.1 kHz, 19.2 kHz at 48 kHz), -0.44 dB at 0.45 fs, -6 dB at
    // 0.5 fs, and at least 90 dB down from 0.593 fs (26.2 kHz at 44.1 kHz, 28.5 kHz at 48 kHz) on.
    // What folds back below 0.407 fs is therefore 90 dB down. 63 taps cannot also put 90 dB at
    // 0.55 fs: that takes 119 (Kaiser beta 9.2, 92 dB from 0.55 fs, 29 frames of latency).
    static constexpr int kTaps = 63;
    static constexpr int kCentre = (kTaps - 1) / 2;
    static constexpr int kSide = (kCentre + 1) / 2;      // the non-zero taps on one side of the centre
    static_assert(kTaps % 4 == 3, "a half-band filter whose outermost taps are not zero");

    // The Kaiser window's shape: 90 dB in the stopband. Kaiser's beta = 0.1102 (A - 8.7) gives
    // 8.96 for A = 90; 9.0 measures 89.4 dB, 9.1 the first 90.
    static constexpr double kBeta = 9.1;

    // How many host frames the output lags the input. The output is taken at the second sample of
    // each pair; the centre tap then sits on the first sample of the pair (kCentre - 1) / 2 pairs
    // back, so the delay is a whole number of host frames.
    static constexpr int kLatency = (kCentre - 1) / 2;

    // The taps: h(m) = sin(pi m / 2) / (pi m) * w(m) at the odd distances m from the centre, with
    // w the Kaiser window, scaled so that a constant passes at gain 1.
    void design()
    {
        double h[kSide], sum = 0.0;
        for (int k = 0; k < kSide; ++k)
        {
            const int m = 2 * k + 1;
            const double r = (double)m / (double)kCentre;
            const double window = besselI0(kBeta * std::sqrt(1.0 - r * r)) / besselI0(kBeta);
            h[k] = std::sin(kPi * m / 2.0) / (kPi * m) * window;
            sum += 2.0 * h[k];
        }
        for (int k = 0; k < kSide; ++k) coef_[k] = (float)(h[k] * 0.5 / sum);   // the sides add up to 1/2
        reset();
    }

    void reset()
    {
        for (float& x : line_) x = 0.0f;
        newest_ = 0;
    }

    // Two input samples in, in order; one output sample out.
    float process(float first, float second)
    {
        push(first);
        push(second);
        const float* x = line_ + newest_;                    // x[j]: the input j samples ago
        float y = 0.5f * x[kCentre];
        for (int k = 0; k < kSide; ++k) y += coef_[k] * (x[kCentre - 1 - 2 * k] + x[kCentre + 1 + 2 * k]);
        return y;
    }

private:
    static constexpr double kPi = 3.14159265358979323846;

    // The modified Bessel function of the first kind, order 0, by its power series.
    static double besselI0(double x)
    {
        double sum = 1.0, term = 1.0;
        for (int k = 1; k < 64 && term > 1e-17 * sum; ++k)
        {
            const double half = x / (2.0 * k);
            term *= half * half;
            sum += term;
        }
        return sum;
    }

    // The delay line, written twice (at i and at i + kTaps) so that the last kTaps inputs always
    // lie in one piece from newest_ on.
    void push(float x)
    {
        newest_ = newest_ == 0 ? kTaps - 1 : newest_ - 1;
        line_[newest_] = x;
        line_[newest_ + kTaps] = x;
    }

    float  coef_[kSide] = {};                                // the taps at distances 1, 3, ... kCentre
    float  line_[2 * kTaps] = {};
    int    newest_ = 0;
};

} // namespace brumle
