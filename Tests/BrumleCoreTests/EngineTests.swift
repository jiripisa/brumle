import Accelerate
import Foundation
import Testing
import BrumleDSP
@testable import BrumleCore

/// What the sound engine promises beyond matching the prototype: its level, how it chokes and
/// stops, how it keeps its pitch and its sound at every sample rate, how it shares its voices, and
/// how its C interface copes with what callers hand it.
@Suite("Engine")
struct EngineTests: EngineHarness {

    /// The same with no breath. The breath gives the bursts a DC component, and the DC blocker
    /// takes ~20 ms to forget it after a voice stops: that would hide what the reed does.
    private static let dry = plain.merging(["breath": 0, "puff": 0]) { $1 }

    @Test("The default hit at full velocity peaks around -6 dBFS")
    func level() {
        let engine = makeEngine()
        defer { brumle_destroy(engine) }
        brumle_midi(engine, 0x90, 36, 127, 0)
        let peak = render(engine, seconds: 2).map(abs).max() ?? 0
        #expect(peak > 0.42 && peak < 0.56, "peak \(peak)")
    }

    @Test("A note re-struck chokes its own ring within Damp")
    func restrike() {
        let length = Int(Self.rate)
        let twice = makeEngine(Self.dry)
        defer { brumle_destroy(twice) }
        brumle_midi(twice, 0x90, 36, 110, 0)
        _ = render(twice, frames: length)
        brumle_midi(twice, 0x90, 36, 110, 0)
        let second = render(twice, frames: length)

        let once = makeEngine(Self.dry)
        defer { brumle_destroy(once) }
        brumle_midi(once, 0x90, 36, 110, 0)
        let lone = render(once, frames: length)

        // The first ring is gone after Damp (10 ms): from then on the two are the same hit.
        let damp = Int(0.010 * Self.rate)
        let r = residualDb(second[damp...], lone[damp...])
        #expect(r < -60, "residual \(r) dB")
    }

    @Test("Key Up = Damp stops the note at note-off; Ring lets it ring")
    func keyUp() {
        func afterRelease(_ keyUp: Float) -> (sounding: Int32, rms: Double) {
            let engine = makeEngine(Self.dry.merging(["keyup": keyUp]) { $1 })
            defer { brumle_destroy(engine) }
            brumle_midi(engine, 0x90, 36, 110, 0)
            _ = render(engine, seconds: 0.5)
            brumle_midi(engine, 0x80, 36, 0, 0)
            _ = render(engine, seconds: 0.05)           // Damp is 10 ms: 100 dB down in 25 ms
            let sounding = brumle_sounding_voices(engine)
            return (sounding, rms(render(engine, seconds: 0.2)))
        }
        let ring = afterRelease(0), damp = afterRelease(1)
        #expect(ring.sounding == 1 && damp.sounding == 0)
        #expect(ring.rms > 0.001)
        #expect(20 * log10(damp.rms / ring.rms) < -60, "damped \(damp.rms), ringing \(ring.rms)")
    }

    @Test("All Sound Off and All Notes Off choke every voice")
    func allOff() {
        for controller: Int32 in [120, 123] {
            let engine = makeEngine(Self.plain)
            defer { brumle_destroy(engine) }
            brumle_midi(engine, 0x90, 36, 110, 0)
            brumle_midi(engine, 0x90, 43, 110, 0)
            _ = render(engine, seconds: 0.2)
            #expect(brumle_sounding_voices(engine) == 2)
            brumle_midi(engine, 0xB0, controller, 0, 0)
            _ = render(engine, seconds: 0.05)
            #expect(brumle_sounding_voices(engine) == 0, "CC \(controller)")
        }
    }

    /// The bus's DC blocker, as the engine computes it at 96 kHz.
    private static let dcCoefficient = Float(1 - 48 / rate)

    // What is left once the voices stop is the DC blocker's memory of the reed's DC (Offset
    // makes the bursts lopsided): it falls by the blocker's coefficient every sample, -4.2 dB in
    // 10 ms, and is under -120 dBFS ~110 ms after the controller. So the test asks for no voice
    // in the bus after 50 ms, which is exact, and for -120 dBFS after 150 ms.
    @Test("After All Sound Off or All Notes Off the voices are silent within 50 ms")
    func allOffFallsSilent() {
        for controller: Int32 in [120, 123] {
            let engine = makeEngine(Self.dry)
            defer { brumle_destroy(engine) }
            brumle_midi(engine, 0x90, 36, 110, 0)
            brumle_midi(engine, 0x90, 43, 110, 0)
            #expect((render(engine, seconds: 0.2).map(abs).max() ?? 0) > 0.05)
            brumle_midi(engine, 0xB0, controller, 0, 0)
            _ = render(engine, seconds: 0.05)
            let tail = render(engine, seconds: 0.1)
            let onlyTheBlocker = zip(tail.dropFirst(), tail).allSatisfy { next, previous in
                previous == 0 ? next == 0 : abs(next / previous - Self.dcCoefficient) < 1e-5
            }
            #expect(onlyTheBlocker, "CC \(controller): a voice is still in the bus 50 ms after it")
            let peak = render(engine, seconds: 0.5).map(abs).max() ?? 0
            #expect(peak == 0 || 20 * log10(peak) < -120, "CC \(controller): \(20 * log10(peak)) dBFS after 150 ms")
        }
    }

    @Test("Silence is exact 20 s after the last hit")
    func silenceIsExact() {
        let engine = makeEngine()
        defer { brumle_destroy(engine) }
        brumle_midi(engine, 0x90, 36, 127, 0)
        brumle_midi(engine, 0x90, 43, 90, 64)
        _ = render(engine, seconds: 20)
        #expect(brumle_sounding_voices(engine) == 0)
        let tail = render(engine, seconds: 1)
        #expect(tail.allSatisfy { $0 == 0 && $0.sign == .plus })
    }

    @Test("A requested reset silences at the next block")
    func requestedReset() {
        let engine = makeEngine()
        defer { brumle_destroy(engine) }
        brumle_post_midi(engine, 0x90, 36, 127, 0)
        #expect((render(engine, seconds: 0.5).map(abs).max() ?? 0) > 0.05)
        brumle_request_reset(engine)             // what a host's AudioUnitReset does, from any thread
        #expect(render(engine, frames: 128).allSatisfy { $0 == 0 })
        #expect(render(engine, seconds: 0.5).allSatisfy { $0 == 0 })
        #expect(brumle_sounding_voices(engine) == 0)
    }

    @Test("A reset forgets the last note; MIDI posted before a requested reset plays after it")
    func resetAndPostedMidi() {
        let engine = makeEngine()
        defer { brumle_destroy(engine) }
        brumle_midi(engine, 0x90, 43, 110, 0)
        _ = render(engine, frames: 128)
        #expect(brumle_last_note(engine) == 43)
        brumle_reset(engine)
        #expect(brumle_last_note(engine) == -1)

        brumle_post_midi(engine, 0x90, 36, 110, 0)
        brumle_request_reset(engine)
        #expect((render(engine, seconds: 0.2).map(abs).max() ?? 0) > 0.05)
        #expect(brumle_last_note(engine) == 36)
    }

    @Test("MIDI at a sample offset starts the hit at that sample")
    func sampleOffset() {
        let engine = makeEngine(Self.plain)
        defer { brumle_destroy(engine) }
        brumle_midi(engine, 0x90, 36, 110, 37)
        let out = render(engine, frames: 128)
        #expect(out[..<37].allSatisfy { $0 == 0 })
        #expect(out[37...].contains { $0 != 0 })
    }

    @Test("Each set keeps its own knobs and program")
    func setsAreSeparate() {
        let engine = makeEngine()
        defer { brumle_destroy(engine) }
        let ring = Self.index("ring")
        brumle_set_plain(engine, 5, ring, 1)
        brumle_set_program(engine, 3, 2)
        #expect(abs(brumle_get_plain(engine, Self.keyboard, ring) - 4) < 1e-5)   // stored normalised
        #expect(abs(brumle_get_plain(engine, 5, ring) - 1) < 1e-5)
        #expect(brumle_get_program(engine, 3) == 2 && brumle_get_program(engine, Self.keyboard) == 0)
        #expect(abs(brumle_get_plain(engine, 3, ring) - 8) < 1e-5)     // Khomus rings 8 s
        brumle_set_normalised(engine, 16, ring, 0.25)
        #expect(brumle_get_normalised(engine, 16, ring) == 0.25)
    }

    @Test("The C interface tolerates a null engine and indices out of range")
    func outOfRange() {
        let engine = makeEngine()
        defer { brumle_destroy(engine) }
        let ring = Self.index("ring")
        for set: Int32 in [-1, 17] {
            brumle_set_plain(engine, set, ring, 1)
            brumle_set_normalised(engine, set, ring, 1)
            brumle_set_program(engine, set, 1)
            #expect(brumle_get_plain(engine, set, ring) == 0 && brumle_get_normalised(engine, set, ring) == 0)
            #expect(brumle_get_program(engine, set) == 0)
        }
        for index: Int32 in [-1, Int32(brumle_num_params())] {
            brumle_set_plain(engine, Self.keyboard, index, 1)
            #expect(brumle_get_plain(engine, Self.keyboard, index) == 0)
        }
        brumle_set_program(engine, Self.keyboard, -1)
        brumle_set_program(engine, Self.keyboard, brumle_num_programs())
        #expect(brumle_get_program(engine, Self.keyboard) == 0)
        brumle_set_mode(engine, 7)
        #expect(brumle_get_mode(engine) == Int32(BRUMLE_MODE_KEYBOARD))
        for pad: Int32 in [-1, 16] {
            brumle_set_pad_note(engine, pad, 40)
            brumle_set_pad_group(engine, pad, 2)
            brumle_send_to_pad(engine, pad)
            #expect(brumle_pad_note(engine, pad) == -1 && brumle_pad_group(engine, pad) == 0)
        }
        let group = brumle_pad_group(engine, 0)
        brumle_set_pad_group(engine, 0, 17)
        brumle_set_pad_group(engine, 0, -1)
        #expect(brumle_pad_group(engine, 0) == group)
        #expect(abs(brumle_get_plain(engine, Self.keyboard, ring) - 4) < 1e-5)

        // A null engine: every call returns quietly.
        var left = [Float](repeating: 1, count: 16)
        brumle_destroy(nil)
        brumle_prepare(nil, 48_000); brumle_reset(nil); brumle_request_reset(nil)
        brumle_set_plain(nil, 0, ring, 1); brumle_set_normalised(nil, 0, ring, 1); brumle_set_program(nil, 0, 1)
        brumle_set_mode(nil, 1); brumle_set_pad_note(nil, 0, 40); brumle_set_pad_group(nil, 0, 1)
        brumle_send_to_pad(nil, 0); brumle_load_default_kit(nil)
        brumle_post_midi(nil, 0x90, 36, 100, 0); brumle_midi(nil, 0x90, 36, 100, 0)
        left.withUnsafeMutableBufferPointer { brumle_process(nil, $0.baseAddress, nil, 16) }
        #expect(left.allSatisfy { $0 == 0 })
        #expect(brumle_get_plain(nil, 0, ring) == 0 && brumle_get_program(nil, 0) == 0 && brumle_get_mode(nil) == 0)
        #expect(brumle_latency(nil) == 0 && brumle_sounding_voices(nil) == 0 && brumle_last_note(nil) == -1)
        #expect(brumle_pad_note(nil, 0) == -1 && brumle_pad_group(nil, 0) == 0)

        var info = BrumleParamInfo()
        brumle_param_info(ring, &info)
        brumle_param_info(-1, &info)
        #expect(info.identifier == nil && info.kind == 0 && info.maxValue == 0)
    }
    // MARK: - Sample rates and oversampling

    /// The fundamental of `x` in Hz: the autocorrelation's highest peak from its first zero
    /// crossing up to 1.5 periods of `expected`, placed between samples by a parabola. The window
    /// keeps out an octave error (half or twice the period) without steering the answer.
    private func fundamental(_ x: [Float], rate: Double, expected: Double) -> Double {
        let maxLag = Int(1.5 * rate / expected)
        let length = x.count - maxLag
        var r = [Float](repeating: 0, count: maxLag + 1)
        x.withUnsafeBufferPointer { signal in
            vDSP_conv(signal.baseAddress!, 1, signal.baseAddress!, 1, &r, 1, vDSP_Length(maxLag + 1), vDSP_Length(length))
        }
        guard let firstNegative = r.firstIndex(where: { $0 < 0 }) else { return 0 }
        var best = firstNegative
        for lag in firstNegative..<maxLag where r[lag] > r[best] { best = lag }
        guard best > firstNegative && best < maxLag else { return rate / Double(best) }
        let a = Double(r[best - 1]), b = Double(r[best]), c = Double(r[best + 1])
        return rate / (Double(best) + 0.5 * (a - c) / (a - 2 * b + c))
    }

    /// Molln (its mouth held still) on note 57, A3, rendered by `engine` at `rate`: its fundamental
    /// from 0.3 s to 0.55 s.
    private func mollnPitch(_ engine: OpaquePointer, rate: Double) -> Double {
        brumle_midi(engine, 0x90, 57, 110, 0)
        let out = render(engine, seconds: 0.55, at: rate)
        return fundamental(Array(out[Self.frames(0.3, at: rate)...]), rate: rate, expected: 220)
    }

    private func mollnEngine(rate: Double) -> OpaquePointer {
        let engine = makeEngine(rate: rate)
        brumle_set_program(engine, Self.keyboard, 1)          // Molln: Sweep 0
        return engine
    }

    @Test("The pitch is right at every rate", arguments: [44_100.0, 48_000, 88_200, 96_000, 192_000])
    func pitchAtEveryRate(rate: Double) {
        let engine = mollnEngine(rate: rate)
        defer { brumle_destroy(engine) }
        let hz = mollnPitch(engine, rate: rate)
        #expect(abs(hz / 220 - 1) < 0.001, "\(rate) Hz: \(hz) Hz")
    }

    /// The share of the power below 20 kHz that lies more than 20 Hz from every harmonic of
    /// `f0`, in dB: what aliasing folds between the harmonics. A Blackman-Harris window over
    /// 0.68 s from 0.2 s into the hit, when Clang (20 ms) has died away.
    private func aliasDb(_ x: [Float], rate: Double, f0: Double) -> Double {
        let log2n = vDSP_Length(rate < 88_200 ? 15 : 16)
        let n = 1 << Int(log2n)
        let start = Self.frames(0.2, at: rate)
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { preconditionFailure("no FFT") }
        defer { vDSP_destroy_fftsetup(setup) }
        let frame = (0..<n).map { i -> Float in
            let p = 2 * Double.pi * Double(i) / Double(n - 1)
            let w = 0.35875 - 0.48829 * cos(p) + 0.14128 * cos(2 * p) - 0.01168 * cos(3 * p)
            return x[start + i] * Float(w)
        }
        var real = [Float](repeating: 0, count: n / 2), imag = [Float](repeating: 0, count: n / 2)
        var power = [Float](repeating: 0, count: n / 2)
        real.withUnsafeMutableBufferPointer { r in
            imag.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                frame.withUnsafeBytes { bytes in
                    vDSP_ctoz(bytes.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(n / 2))
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                power.withUnsafeMutableBufferPointer { m in vDSP_zvmags(&split, 1, m.baseAddress!, 1, vDSP_Length(n / 2)) }
            }
        }
        var between = 0.0, total = 0.0
        for bin in 1..<(n / 2) {
            let hz = Double(bin) * rate / Double(n)
            guard hz < 20_000 else { break }
            total += Double(power[bin])
            if abs(hz - f0 * (hz / f0).rounded()) > 20 { between += Double(power[bin]) }
        }
        return 10 * log10(between / total)
    }

    // At 48 kHz the voices run at 96 kHz, as they do at a 96 kHz host, and the decimator keeps
    // what would fold back out of the band below 20 kHz.
    @Test("At 48 kHz the bright high note aliases no more than at 96 kHz")
    func aliasing() {
        let bright: [String: Float] = ["edge": 40, "vary": 0, "air": 0, "breath": 0, "puff": 0]
        let f0 = 440 * pow(2, (84 - 69) / 12.0)
        func alias(at rate: Double) -> Double {
            let engine = makeEngine(bright, rate: rate)
            defer { brumle_destroy(engine) }
            brumle_midi(engine, 0x90, 84, 110, 0)
            return aliasDb(render(engine, seconds: 1, at: rate), rate: rate, f0: f0)
        }
        let at48 = alias(at: 48_000), at96 = alias(at: 96_000)
        #expect(at48 <= at96 + 3, "48 kHz: \(at48) dB, 96 kHz: \(at96) dB")
    }

    // Below 88.2 kHz the output is the voices at twice the rate, decimated: the same hit at the
    // doubled rate, taken every second sample, lags behind by the decimator's delay. The hit is
    // 37 frames into the block at the host rate and 74 at the doubled rate: the same instant.
    @Test("Latency is the decimator's delay")
    func latency() {
        for rate in [44_100.0, 48_000] {
            let host = makeEngine(Self.plain, rate: rate), doubled = makeEngine(Self.plain, rate: 2 * rate)
            defer { brumle_destroy(host); brumle_destroy(doubled) }
            #expect(brumle_latency(doubled) == 0)
            let latency = Int(brumle_latency(host))
            #expect(latency > 0, "\(rate) Hz")
            brumle_midi(host, 0x90, 36, 110, 37)
            brumle_midi(doubled, 0x90, 36, 110, 74)
            let y = render(host, seconds: 0.5, at: rate), z = render(doubled, seconds: 0.5, at: 2 * rate)
            func correlation(_ lag: Int) -> Double {
                var sum = 0.0
                for m in lag..<(y.count - 64) { sum += Double(y[m]) * Double(z[2 * (m - lag)]) }
                return sum
            }
            let best = (0...64).max { correlation($0) < correlation($1) }!
            #expect(abs(best - latency) <= 1, "\(rate) Hz: best lag \(best), latency \(latency)")
        }
        for rate in [88_200.0, 96_000, 192_000] {
            let engine = makeEngine(rate: rate)
            defer { brumle_destroy(engine) }
            #expect(brumle_latency(engine) == 0, "\(rate) Hz")
        }
    }

    // A rate change mid-ring starts from silence: the first block is exactly zero, and what is
    // played then is what a fresh engine at that rate plays, sample for sample.
    @Test("Re-preparing changes the rate cleanly")
    func rePrepareChangesRate() {
        let engine = mollnEngine(rate: 96_000)
        defer { brumle_destroy(engine) }
        #expect(abs(mollnPitch(engine, rate: 96_000) / 220 - 1) < 0.001)
        for rate in [44_100.0, 96_000] {
            brumle_prepare(engine, rate)                       // the last note still rings
            let first = render(engine, frames: 128)
            #expect(first.allSatisfy { $0 == 0 }, "\(rate) Hz: the first block after prepare")
            let hz = mollnPitch(engine, rate: rate)
            #expect(abs(hz / 220 - 1) < 0.001, "\(rate) Hz: \(hz) Hz")
            brumle_reset(engine)
            brumle_midi(engine, 0x90, 57, 110, 0)
            let again = render(engine, seconds: 0.5, at: rate)
            let fresh = mollnEngine(rate: rate)
            defer { brumle_destroy(fresh) }
            brumle_midi(fresh, 0x90, 57, 110, 0)
            #expect(again == render(fresh, seconds: 0.5, at: rate), "\(rate) Hz: differs from a fresh engine")
        }
    }

    // Every knob at its minimum, every knob at its maximum (Pan too: one channel is silent), and
    // the sharpest mouth swept to the top on a high note. Each is played from the lowest note to
    // the highest, hard and soft.
    @Test("Extreme knobs stay finite", arguments: [44_100.0, 96_000])
    func extremeKnobsStayFinite(rate: Double) {
        func play(_ setKnobs: (OpaquePointer) -> Void, notes: [Int32]) -> (left: [Float], right: [Float]) {
            let engine = makeEngine(rate: rate)
            defer { brumle_destroy(engine) }
            setKnobs(engine)
            var out: (left: [Float], right: [Float]) = ([], [])
            for note in notes {
                for velocity: Int32 in [127, 1] {
                    brumle_midi(engine, 0x90, note, velocity, 0)
                    let part = renderStereo(engine, frames: Self.frames(0.25, at: rate))
                    out.left += part.left; out.right += part.right
                }
            }
            let tail = renderStereo(engine, frames: Self.frames(1, at: rate))
            return (out.left + tail.left, out.right + tail.right)
        }
        let everyNote: [Int32] = [0, 24, 36, 60, 84, 96, 108, 127]
        let all: (Float) -> (OpaquePointer) -> Void = { n in
            { engine in for i in 0..<brumle_num_params() { brumle_set_normalised(engine, Self.keyboard, i, n) } }
        }
        let cases: [(name: String, render: (left: [Float], right: [Float]))] = [
            ("all at minimum", play(all(0), notes: everyNote)),
            ("all at maximum", play(all(1), notes: everyNote)),
            ("Reso 40, Vowel 3300 Hz, Sweep +24 st",
             play({ self.setKnobs($0, ["reso": 40, "vowel": 3300, "sweep": 24]) }, notes: [96])),
        ]
        for c in cases {
            let samples = c.render.left + c.render.right
            #expect(samples.allSatisfy { $0.isFinite }, "\(rate) Hz, \(c.name): NaN or Inf")
            let peak = samples.map(abs).max() ?? 0
            #expect(peak <= 1, "\(rate) Hz, \(c.name): peak \(peak)")
            #expect(peak > 0, "\(rate) Hz, \(c.name): silent")
        }
    }

    // MARK: - The voice pool

    /// Plays `hits` (note, velocity) at every 32nd note at 120 BPM for 4 s, in `mode`, with Ring
    /// 15 s in every set and every pad's group Off, and checks the pool after every block.
    private func flood(rate: Double, mode: Int32, hits: (Int) -> [(note: Int32, velocity: Int32)]) {
        let engine = makeEngine(rate: rate)
        defer { brumle_destroy(engine) }
        brumle_set_mode(engine, mode)
        for set: Int32 in 0..<Int32(BRUMLE_NUM_SETS) { brumle_set_plain(engine, set, Self.index("ring"), 15) }
        for pad: Int32 in 0..<Int32(BRUMLE_NUM_PADS) { brumle_set_pad_group(engine, pad, 0) }
        let step = 60.0 / 120 / 8, total = Self.frames(4, at: rate)
        var out = [Float](repeating: 0, count: total)
        var nextStep = 0, start = 0, mostSounding: Int32 = 0
        out.withUnsafeMutableBufferPointer { buffer in
            while start < total {
                let count = min(128, total - start)
                while Self.frames(Double(nextStep) * step, at: rate) < start + count {
                    let offset = Int32(Self.frames(Double(nextStep) * step, at: rate) - start)
                    for hit in hits(nextStep) { brumle_midi(engine, 0x90, hit.note, hit.velocity, offset) }
                    nextStep += 1
                }
                brumle_process(engine, buffer.baseAddress! + start, nil, Int32(count))
                mostSounding = max(mostSounding, brumle_sounding_voices(engine))
                start += count
            }
        }
        let name = mode == Int32(BRUMLE_MODE_PADS) ? "pads" : "keyboard"
        #expect(mostSounding <= Int32(BRUMLE_MAX_VOICES), "\(rate) Hz, \(name): \(mostSounding) voices sounded")
        #expect(mostSounding == Int32(BRUMLE_MAX_VOICES), "\(rate) Hz, \(name): the pool was never full")
        #expect(out.allSatisfy { $0.isFinite }, "\(rate) Hz, \(name): NaN or Inf")
        let biggestStep = zip(out.dropFirst(), out).map { abs($0 - $1) }.max() ?? 0
        #expect(biggestStep <= 1, "\(rate) Hz, \(name): a step of \(biggestStep)")
    }

    // All 16 pads of the default kit, in no group, on every 32nd note, each a little softer than
    // the one before it in turn: at every step sixteen voices start while the sixteen before them
    // are choked, more than the pool's 20 slots. And the keyboard running up 24 keys, a key per
    // 32nd note: 24 voices would ring.
    @Test("A flood of hits stays within 16 voices", arguments: [44_100.0, 96_000])
    func stealingStaysBounded(rate: Double) {
        flood(rate: rate, mode: Int32(BRUMLE_MODE_PADS)) { step in
            (0..<Int32(BRUMLE_NUM_PADS)).map { (Int32(BRUMLE_FIRST_PAD_NOTE) + $0, Int32(127 - 3 * ((Int($0) + step) % 16))) }
        }
        flood(rate: rate, mode: Int32(BRUMLE_MODE_KEYBOARD)) { step in [(Int32(36 + step % 24), Int32(127))] }
    }

    // Sixteen keys ring, the first one soft, and a 17th steals the soft key's voice: what is heard
    // is the soft key damped in 3 ms as the 17th is struck, the other fifteen ringing on.
    @Test("The quietest voice is stolen, with a 3 ms fade")
    func stealsTheQuietest() {
        func play(releasing: Bool) -> [Float] {
            let engine = makeEngine(Self.dry.merging(["ring": 15, "keyup": 1, "damp": 3, "volume": -24]) { $1 })
            defer { brumle_destroy(engine) }
            brumle_midi(engine, 0x90, 40, 20, 0)
            for note: Int32 in 41..<56 { brumle_midi(engine, 0x90, note, 127, 0) }
            var out = render(engine, seconds: 0.2)
            #expect(brumle_sounding_voices(engine) == 16)
            if releasing { brumle_midi(engine, 0x80, 40, 0, 0) }
            brumle_midi(engine, 0x90, 60, 127, 0)
            out += render(engine, seconds: 0.3)
            #expect(brumle_sounding_voices(engine) == 16)
            return out
        }
        let r = residualDb(play(releasing: false), play(releasing: true))
        #expect(r < -100, "residual \(r) dB")
    }
}
