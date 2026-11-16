// brumle_spike.cpp - THROWAWAY listening prototype for Brumle's sound (not product code).
//
// One voice = the research report's recommended model:
//   reed   a decaying sine at the note's pitch, released at full deflection
//   slot   each passage through the frame makes a burst: gate(u) * (v + b) * |v + b|
//   mouth  three resonators in parallel struck by the bursts (throat, moving vowel, fixed high)
//          plus the bursts themselves (buzz) and a trace of the reed's motion (body)
// Renders WAV files (96 kHz, 24 bit, peak-normalised to -1 dBFS) for the report's twelve
// questions for the author's ear.
//
//   clang++ -std=c++17 -O2 brumle_spike.cpp -o brumle_spike && ./brumle_spike <outdir>
//   ./brumle_spike --analyze     prints the default hit's harmonic levels

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <random>
#include <string>
#include <vector>

static constexpr double SR = 96000.0;
static constexpr double kPi = 3.14159265358979323846;

struct Params
{
    float ring = 4.0f;          // s, reed's own 60 dB time
    float edge = 18.0f;         // swing at a full stroke, in slot half-widths
    float offset = 0.2f;        // rest position against the frame plane, half-widths
    float bodyDb = -24.0f;      // reed motion heard directly, re the strongest harmonic (approx.)
    float buzz = 0.4f;          // bursts heard directly
    float clang = 0.1f;         // second bending mode in the first ~50 ms
    float velsens = 0.7f;
    int stroke = 2;             // 0 out, 1 in, 2 alternate
    float damp = 10.0f;         // ms, finger stopping the reed
    float vary = 0.2f;
    float vowel = 800.0f;       // Hz, where the moving resonance starts
    float sweep = 14.0f;        // semitones travelled during the hit
    float sweeptime = 160.0f;   // ms
    int curve = 0;              // 0 glide, 1 line, 2 there-and-back, 3 step
    float reso = 15.0f;         // Q of the moving resonance
    float throatDb = -10.0f;    // throat resonance level re the moving one
    float throattune = 430.0f;  // Hz
    float open = 0.3f;          // throat openness
    float close = 0.0f;         // tongue shutting the moving resonance
    float breath = 0.3f;        // -1 (in) .. +1 (out); 1 = half the reed's speed at a full stroke
    float puff = 0.3f;          // breath pushed at the stroke
    float pufftime = 120.0f;    // ms
    float air = 0.1f;           // breath noise
    bool levelOnlyVelocity = false;
};

// Trapezoidal state-variable band-pass (as Didgeridoo's TractResonance). Returns the band-pass
// state, whose peak gain is Q: a sharper mouth resonance rings louder, as a struck one does.
struct Reso
{
    float k = 0.1f, a1 = 1, a2 = 0, a3 = 0, ic1 = 0, ic2 = 0;
    void set(float hz, float q)
    {
        hz = std::min(hz, (float)(0.45 * SR));
        const float g = (float)std::tan(kPi * hz / SR);
        k = 1.0f / q;
        a1 = 1.0f / (1.0f + g * (g + k)); a2 = g * a1; a3 = g * a2;
    }
    float step(float x)
    {
        const float v3 = x - ic2, v1 = a1 * ic1 + a2 * v3, v2 = ic2 + a2 * ic1 + a3 * v3;
        ic1 = 2 * v1 - ic1; ic2 = 2 * v2 - ic2;
        return v1;
    }
};

static float dbToGain(float db) { return std::pow(10.0f, db / 20.0f); }

// Level of one harmonic the vowel resonance brings out, in the output's units, for a full
// stroke: calibrates Body against the strongest harmonic (set from --analyze).
static constexpr float kHarmonicRef = 0.35f;

// Added 2026-11-16, after the author's listening heard hiss in long tails: the slot's gate is open
// while the reed rests, so Air and the breath bias went on at a constant level until the voice
// retired. Both now fade with the reed's own decay (1 at the hit):
static constexpr float kAirFadeBelow = 0.1f;        // Air fades with the reed once it is 20 dB down
static constexpr float kBreathFadeBelow = 0.001f;   // the breath fades over the reed's last 40 dB: no step at retire

struct Voice
{
    bool active = false, choking = false;
    int note = 0;
    Params p;
    double phase = 0, inc = 0, t = 0;
    float swing = 1, tau = 1, dir = 1, offset = 0, vowelStart = 800, sweepTime = 0.16f;
    float vel = 1, outGain = 1, chokeGain = 1, chokeMul = 1, puffAmt = 0;
    int ctl = 0;
    float vowelHz = 800;
    Reso vowelR, throatR, highR;
    std::minstd_rand noise{1};

    void start(int n, float velocity, const Params& params, float direction, std::mt19937& rng)
    {
        *this = Voice();
        active = true; note = n; p = params; vel = velocity; dir = direction;
        const double f0 = 440.0 * std::pow(2.0, (n - 69) / 12.0);
        inc = 2 * kPi * f0 / SR;
        std::uniform_real_distribution<float> u(-1.0f, 1.0f);
        const float vy = p.vary;
        const float v = p.levelOnlyVelocity ? 1.0f : 1.0f - p.velsens * (1.0f - velocity);
        swing = v * (1.0f + 0.15f * vy * u(rng));
        outGain = p.levelOnlyVelocity ? velocity : 1.0f;
        tau = p.ring / 6.91f;
        offset = p.offset + 0.3f * vy * u(rng);
        vowelStart = p.vowel * std::pow(2.0f, 3.0f * vy * u(rng) / 12.0f);
        sweepTime = p.sweeptime * 0.001f * (1.0f + 0.2f * vy * u(rng));
        puffAmt = p.puff * (p.levelOnlyVelocity ? 1.0f : (0.3f + 0.7f * velocity));
        noise.seed((unsigned)(rng() | 1));
        ctl = 0;
    }

    void choke()
    {
        if (choking) return;
        choking = true;
        const float tc = std::max(p.damp, 1.0f) * 0.001f / 4.6f;   // -40 dB in Damp
        chokeMul = (float)std::exp(-1.0 / (tc * SR));
    }

    float shape(float x) const
    {
        x = std::clamp(x, 0.0f, 1.0f);
        switch (p.curve)
        {
            case 1: return x;
            case 2: return (float)std::sin(kPi * x);
            case 3: return x < 0.5f ? 0.0f : 1.0f;
            default: return 1.0f - (1.0f - x) * (1.0f - x) * (1.0f - x);
        }
    }

    void updateFilters()
    {
        const float tt = (float)t;
        vowelHz = std::clamp(vowelStart * std::pow(2.0f, p.sweep * shape(tt / sweepTime) / 12.0f), 150.0f, 9000.0f);
        vowelR.set(vowelHz, p.reso);
        const float q = 6.0f - 3.5f * p.open;
        throatR.set(p.throattune + 250.0f * p.open, q);
        highR.set(2800.0f, 4.0f);
    }

    float process()
    {
        if (ctl-- <= 0) { updateFilters(); ctl = 15; }
        const float a = swing * (float)std::exp(-t / tau) * chokeGain;
        const float c = (float)std::cos(phase), s = (float)std::sin(phase);
        float u = dir * p.edge * a * c + offset;
        if (p.clang > 0) u += p.clang * 3.0f * a * (float)std::exp(-t / 0.02) * (float)std::sin(6.27 * phase);
        const float v = -dir * a * s;
        const float pt = p.pufftime * 0.001f;
        const float puffEnv = t < pt ? (float)(1.0 - t / pt) : 0.0f;
        const float ra = a / swing;   // added 2026-11-16 (the author's listening): Air and breath fade with the reed
        const float gN = std::min(1.0f, ra / kAirFadeBelow);
        const float gB = std::min(1.0f, ra / kBreathFadeBelow);
        const float b = gB * (0.5f * p.breath + 0.5f * puffAmt * puffEnv * (p.breath < 0 ? -1.0f : 1.0f));
        const float th = std::tanh(u);
        const float gate = 1.0f - th * th;
        float src = gate * (v + b) * std::fabs(v + b);
        const float n = (float)noise() / (float)noise.max() * 2.0f - 1.0f;
        src += gN * (p.air * 0.08f * n * (gate + 0.05f) * (0.3f + std::fabs(b)));

        const float vowelGain = (1.0f - p.close);
        const float throatGain = dbToGain(p.throatDb) * (1.0f + p.open);
        float y = vowelGain * vowelR.step(src) * (15.0f / p.reso) * std::sqrt(p.reso / 15.0f)
                + throatGain * throatR.step(src) * 2.0f
                + 0.25f * highR.step(src)
                + p.buzz * src * 1.0f
                + kHarmonicRef * dbToGain(p.bodyDb) * dir * a * c;
        y *= outGain;

        t += 1.0 / SR;
        phase += inc;
        if (phase > 2 * kPi) phase -= 2 * kPi;
        if (choking) { chokeGain *= chokeMul; if (chokeGain < 1e-5f) active = false; }
        if (a < 1e-5f && t > 0.2) active = false;
        return y;
    }
};

struct Event { double time; int note; float vel; Params p; bool chokeOnly = false; };

struct Score
{
    std::vector<Event> ev;
    void hit(double t, int note, float vel, const Params& p) { ev.push_back({t, note, vel, p, false}); }
    void chokeAt(double t, int note, const Params& p) { ev.push_back({t, note, 0, p, true}); }
};

static std::vector<float> render(Score score, double seconds)
{
    std::stable_sort(score.ev.begin(), score.ev.end(), [](const Event& a, const Event& b) { return a.time < b.time; });
    const size_t N = (size_t)(seconds * SR);
    std::vector<float> out(N, 0.0f);
    std::vector<Voice> voices(32);
    std::mt19937 rng(12345);
    int lastDir[128];
    for (int& d : lastDir) d = -1;
    size_t next = 0;
    float x1 = 0, y1 = 0;
    for (size_t i = 0; i < N; ++i)
    {
        const double now = i / SR;
        while (next < score.ev.size() && score.ev[next].time <= now)
        {
            const Event& e = score.ev[next++];
            for (Voice& v : voices) if (v.active && v.note == e.note) v.choke();
            if (e.chokeOnly) continue;
            Voice* slot = nullptr;
            for (Voice& v : voices) if (!v.active) { slot = &v; break; }
            if (!slot) slot = &voices[0];
            float dir = 1;
            if (e.p.stroke == 1) dir = -1;
            else if (e.p.stroke == 2) { lastDir[e.note] = -lastDir[e.note]; dir = (float)lastDir[e.note]; }
            slot->start(e.note, e.vel, e.p, dir, rng);
        }
        float sum = 0;
        for (Voice& v : voices) if (v.active) sum += v.process();
        const float y = sum - x1 + 0.9995f * y1;   // DC blocker
        x1 = sum; y1 = y;
        out[i] = y;
    }
    return out;
}

static void writeWav(const std::string& path, std::vector<float> x)
{
    float peak = 1e-9f;
    for (float v : x) peak = std::max(peak, std::fabs(v));
    const float g = dbToGain(-1.0f) / peak;
    FILE* f = std::fopen(path.c_str(), "wb");
    if (!f) { std::perror(path.c_str()); std::exit(1); }
    const uint32_t sr = (uint32_t)SR, n = (uint32_t)x.size(), dataBytes = n * 3;
    auto u32 = [&](uint32_t v) { std::fwrite(&v, 4, 1, f); };
    auto u16 = [&](uint16_t v) { std::fwrite(&v, 2, 1, f); };
    std::fwrite("RIFF", 1, 4, f); u32(36 + dataBytes); std::fwrite("WAVEfmt ", 1, 8, f);
    u32(16); u16(1); u16(1); u32(sr); u32(sr * 3); u16(3); u16(24);
    std::fwrite("data", 1, 4, f); u32(dataBytes);
    for (float v : x)
    {
        int32_t s = (int32_t)std::lrint(std::clamp(v * g, -1.0f, 1.0f) * 8388607.0f);
        uint8_t b[3] = {(uint8_t)(s & 0xff), (uint8_t)((s >> 8) & 0xff), (uint8_t)((s >> 16) & 0xff)};
        std::fwrite(b, 1, 3, f);
    }
    std::fclose(f);
    std::printf("  %s (peak gain %.1f dB)\n", path.c_str(), 20 * std::log10(g));
}

// ---- scores ------------------------------------------------------------------------------------

static const float kAcc8[8] = {1.0f, .5f, .75f, .5f, .9f, .5f, .75f, .6f};
static const float kAcc16[16] = {1, .45f, .6f, .45f, .85f, .45f, .6f, .5f, .95f, .45f, .6f, .45f, .85f, .5f, .7f, .55f};

// One hit at t0, then a groove from t0 + 2.5 s: 2 bars at 112 BPM, 8ths (sub 2) or 16ths (sub 4).
// chokeAhead > 0 stops the ringing reed that many seconds before each next stroke (Key Up = Damp).
static Score phrase(const Params& p, int note, int sub = 2, double chokeAhead = 0, double t0 = 0.2)
{
    Score s;
    s.hit(t0, note, 0.85f, p);
    const double step = 60.0 / 112.0 / sub;
    const double g0 = t0 + 2.5;
    const int n = 8 * sub / 2 * 2;   // 2 bars
    for (int i = 0; i < n; ++i)
    {
        const double t = g0 + i * step;
        if (chokeAhead > 0 && i > 0) s.chokeAt(t - chokeAhead, note, p);
        const float vel = sub == 4 ? kAcc16[i % 16] : kAcc8[i % 8];
        s.hit(t, note, vel, p);
    }
    return s;
}
static constexpr double kPhraseLen = 2.7 + 2 * 4 * 60.0 / 112.0 + 1.5;

static void analyze(const Params& p, int note)
{
    Score s; s.hit(0.0, note, 1.0f, p);
    const std::vector<float> x = render(s, 1.0);
    const double f0 = 440.0 * std::pow(2.0, (note - 69) / 12.0);
    for (double at : {0.05, 0.6})
    {
        const size_t a = (size_t)(at * SR), len = (size_t)(0.085 * SR);
        std::vector<double> lv;
        for (int k = 1; k <= 60; ++k)
        {
            double re = 0, im = 0;
            for (size_t i = 0; i < len; ++i)
            {
                const double w = 0.5 - 0.5 * std::cos(2 * kPi * i / (len - 1));
                const double ph = 2 * kPi * k * f0 * i / SR;
                re += w * x[a + i] * std::cos(ph); im += w * x[a + i] * std::sin(ph);
            }
            lv.push_back(10 * std::log10(re * re + im * im + 1e-30));
        }
        const double mx = *std::max_element(lv.begin(), lv.end());
        std::printf("t=%.2fs  harmonic levels dB re strongest (k=1..60):\n", at);
        for (int k = 0; k < 60; ++k) std::printf("%4d:%6.1f%s", k + 1, lv[k] - mx, (k % 10 == 9) ? "\n" : "");
    }
    float pk = 0; double rms = 0; const size_t n80 = (size_t)(0.08 * SR);
    for (size_t i = 0; i < n80; ++i) { pk = std::max(pk, std::fabs(x[i])); rms += x[i] * x[i]; }
    std::printf("crest factor first 80 ms: %.1f dB\n", 20 * std::log10(pk / std::sqrt(rms / n80)));
}

int main(int argc, char** argv)
{
    const Params D;
    const int C2 = 36;
    if (argc > 1 && std::strcmp(argv[1], "--analyze") == 0) { analyze(D, C2); return 0; }
    const std::string out = argc > 1 ? argv[1] : "out";
    auto save = [&](const std::string& name, const Score& s, double len = kPhraseLen) { writeWav(out + "/" + name + ".wav", render(s, len)); };
    auto with = [&](auto f) { Params p = D; f(p); return p; };

    save("01_default", phrase(D, C2));

    save("02_ring_A_1s_dry", phrase(with([](Params& p) { p.ring = 1; }), C2));
    save("02_ring_B_4s_default", phrase(D, C2));
    save("02_ring_C_7.5s_long", phrase(with([](Params& p) { p.ring = 7.5f; }), C2));

    save("03_edge_A_9_dark", phrase(with([](Params& p) { p.edge = 9; }), C2));
    save("03_edge_B_18_default", phrase(D, C2));
    save("03_edge_C_30_bright", phrase(with([](Params& p) { p.edge = 30; }), C2));

    save("04_parity_A_bare_odd", phrase(with([](Params& p) { p.offset = 0; p.breath = 0; p.puff = 0; }), C2));
    save("04_parity_B_default_exhale", phrase(D, C2));
    save("04_parity_C_inhale", phrase(with([](Params& p) { p.breath = -0.3f; }), C2));

    save("05_body_A_-24dB_default", phrase(D, C2));
    save("05_body_B_-10dB_more_fundamental", phrase(with([](Params& p) { p.bodyDb = -10; }), C2));

    save("06_tone_A_twang_spring", phrase(with([](Params& p) { p.reso = 8; p.buzz = 0.8f; }), C2));
    save("06_tone_B_default", phrase(D, C2));
    save("06_tone_C_whistle", phrase(with([](Params& p) { p.reso = 30; p.buzz = 0.0f; }), C2));

    save("07_gesture_A_up_160ms_default", phrase(D, C2));
    save("07_gesture_B_up_80ms_fast", phrase(with([](Params& p) { p.sweeptime = 80; }), C2));
    save("07_gesture_C_up_320ms_slow", phrase(with([](Params& p) { p.sweeptime = 320; }), C2));
    save("07_gesture_D_down", phrase(with([](Params& p) { p.vowel = 1800; p.sweep = -14; }), C2));
    save("07_gesture_E_there_and_back", phrase(with([](Params& p) { p.curve = 2; p.sweeptime = 300; }), C2));
    save("07_gesture_F_none", phrase(with([](Params& p) { p.sweep = 0; p.vowel = 1100; }), C2));

    save("08_clang_A_none", phrase(with([](Params& p) { p.clang = 0; }), C2));
    save("08_clang_B_strong", phrase(with([](Params& p) { p.clang = 0.6f; }), C2));

    save("09_restrike_A_choke_10ms_at_stroke", phrase(D, C2, 4));
    save("09_restrike_B_choke_40ms_at_stroke", phrase(with([](Params& p) { p.damp = 40; }), C2, 4));
    save("09_restrike_C_choke_40ms_before_stroke", phrase(D, C2, 4, 0.040));

    save("10_vary_A_0", phrase(with([](Params& p) { p.vary = 0; }), C2, 4));
    save("10_vary_B_20_default", phrase(D, C2, 4));
    save("10_vary_C_50", phrase(with([](Params& p) { p.vary = 0.5f; }), C2, 4));

    for (int which = 0; which < 2; ++which)
    {
        Params p = D; p.levelOnlyVelocity = which == 1;
        Score s;
        for (int i = 0; i < 8; ++i) s.hit(0.2 + 0.7 * i, C2, 0.15f + 0.85f * i / 7.0f, p);
        save(which == 0 ? "11_velocity_A_brightness_and_breath" : "11_velocity_B_level_only", s, 7.0);
    }

    {
        Score s; const int notes[] = {36, 43, 50, 55, 60};   // C2 G2 D3 G3 C4
        for (int i = 0; i < 5; ++i) s.hit(0.2 + 1.6 * i, notes[i], 0.85f, D);
        save("12_range_C2_G2_D3_G3_C4", s, 9.5);
    }

    // Programs (from the report's table), each as a phrase.
    const Params molln = with([](Params& p) { p.ring = 7.5f; p.sweep = 0; p.vowel = 1050; p.reso = 25; p.open = 0; p.offset = 0; });
    const Params khomus = with([](Params& p) { p.ring = 8; p.edge = 26; p.buzz = 0.7f; p.curve = 2; p.sweep = 12; p.sweeptime = 400; });
    const Params morsing = with([](Params& p) { p.ring = 1; p.edge = 26; p.sweeptime = 60; p.puff = 0.8f; p.close = 0.4f; p.damp = 5; });
    const Params danmoi = with([](Params& p) { p.clang = 0; p.open = 0.6f; p.air = 0.3f; p.reso = 10; p.ring = 3; p.stroke = 0; });
    const Params bamboo = with([](Params& p) { p.ring = 1; p.edge = 7; p.clang = 0.6f; p.buzz = 0.15f; p.reso = 8; });
    const Params genggong = with([](Params& p) { p.ring = 0.8f; p.edge = 9; p.clang = 0.4f; p.open = 1.0f; });
    save("13_program_Molln", phrase(molln, C2));
    save("13_program_Khomus", phrase(khomus, 38));
    save("13_program_Morsing", phrase(morsing, 48));
    save("13_program_DanMoi", phrase(danmoi, 39));
    save("13_program_Bamboo", phrase(bamboo, 38));
    save("13_program_Genggong", phrase(genggong, 41));

    // Pads over each other: a small kit, 4 bars at 100 BPM.
    {
        Score s; const double q = 60.0 / 100.0, e = q / 2, sx = q / 4;
        for (int bar = 0; bar < 4; ++bar)
        {
            const double b0 = 0.2 + bar * 4 * q;
            for (int beat : {0, 2}) s.hit(b0 + beat * q, 36, 1.0f, D);                     // C2 "dojng"
            for (int i = 0; i < 4; ++i) s.hit(b0 + i * q + e, 43, 0.6f, molln);             // G2 offbeats
            for (int beat : {1, 3}) s.hit(b0 + beat * q, 48, 0.9f, morsing);                // C3 morsing backbeat
            for (int i = 0; i < 16; ++i) if (i % 4 == 3) s.hit(b0 + i * sx, 39, 0.45f, bamboo);   // D#2 ghosts
        }
        save("14_pads_overlapping_kit", s, 0.2 + 16 * q + 2.0);
    }
    return 0;
}
