import Accelerate
import Foundation
import Testing
import BrumleDSP
@testable import BrumleCore

/// What moves the knobs while the instrument plays: the velocity's amounts, the two LFOs, the
/// knobs themselves turned while a key rings, and the wheels.
@Suite("Modulation")
struct ModulationTests {

    static let rate = 96_000.0
    static let keyboard = Int32(BRUMLE_KEYBOARD_SET)

    private static func index(_ identifier: String) -> Int32 {
        guard let parameter = Parameters.named(identifier) else { preconditionFailure("unknown knob \(identifier)") }
        return Int32(parameter.index)
    }

    /// Out, no randomness: every render here starts from these unless the test says otherwise.
    private static let plain: [String: Float] = ["stroke": 0, "vary": 0, "air": 0]

    /// A fresh engine at 96 kHz in keyboard mode, with `plain` and then `knobs` (plain values) in
    /// the keyboard set.
    private func makeEngine(_ knobs: [String: Float] = [:]) -> OpaquePointer {
        let engine = brumle_create()!
        brumle_prepare(engine, Self.rate)
        brumle_reset(engine)
        brumle_set_mode(engine, Int32(BRUMLE_MODE_KEYBOARD))
        for (key, value) in Self.plain.merging(knobs, uniquingKeysWith: { $1 }) {
            brumle_set_plain(engine, Self.keyboard, Self.index(key), value)
        }
        return engine
    }

    private static func frames(_ seconds: Double) -> Int { Int((seconds * rate).rounded()) }

    /// Renders `frames` of the left channel in blocks of 128 frames.
    private func render(_ engine: OpaquePointer, frames: Int) -> [Float] {
        var out = [Float](repeating: 0, count: frames)
        var start = 0
        out.withUnsafeMutableBufferPointer { buffer in
            while start < frames {
                let count = min(128, frames - start)
                brumle_process(engine, buffer.baseAddress! + start, nil, Int32(count))
                start += count
            }
        }
        return out
    }

    private func render(_ engine: OpaquePointer, seconds: Double) -> [Float] { render(engine, frames: Self.frames(seconds)) }

    /// One hit of C2 at `velocity` on a fresh engine with `knobs`; `before` runs just before the
    /// note-on (for MIDI that sets the wheels).
    private func hit(_ knobs: [String: Float] = [:], velocity: Int32 = 110, seconds: Double = 1.5,
                     before: (OpaquePointer) -> Void = { _ in }) -> [Float] {
        let engine = makeEngine(knobs)
        defer { brumle_destroy(engine) }
        before(engine)
        brumle_midi(engine, 0x90, 36, velocity, 0)
        return render(engine, seconds: seconds)
    }

    private func rms<C: Collection>(_ x: C) -> Double where C.Element == Float {
        (x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(x.count, 1))).squareRoot()
    }

    /// dB of (a - b) re b.
    private func residualDb<A: Collection, B: Collection>(_ a: A, _ b: B) -> Double where A.Element == Float, B.Element == Float {
        var difference = 0.0, signal = 0.0
        for (x, y) in zip(a, b) { difference += Double(x - y) * Double(x - y); signal += Double(y) * Double(y) }
        return 10 * log10(difference / signal)
    }

    /// The magnitude-weighted mean frequency of `x`, in Hz: Hann-windowed frames of 8192 samples.
    private func spectralCentroid(_ x: ArraySlice<Float>) -> Double {
        let log2n: vDSP_Length = 13
        let n = 1 << Int(log2n)
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { preconditionFailure("no FFT") }
        defer { vDSP_destroy_fftsetup(setup) }
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        var weighted = 0.0, total = 0.0
        var start = x.startIndex
        while start + n <= x.endIndex {
            let frame = zip(x[start..<(start + n)], window).map { $0 * $1 }
            var real = [Float](repeating: 0, count: n / 2), imag = [Float](repeating: 0, count: n / 2)
            var magnitudes = [Float](repeating: 0, count: n / 2)
            real.withUnsafeMutableBufferPointer { r in
                imag.withUnsafeMutableBufferPointer { i in
                    var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                    frame.withUnsafeBytes { bytes in
                        vDSP_ctoz(bytes.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(n / 2))
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    magnitudes.withUnsafeMutableBufferPointer { m in
                        vDSP_zvabs(&split, 1, m.baseAddress!, 1, vDSP_Length(n / 2))
                    }
                }
            }
            for bin in 1..<(n / 2) {
                let hz = Double(bin) * Self.rate / Double(n)
                weighted += hz * Double(magnitudes[bin]); total += Double(magnitudes[bin])
            }
            start += n
        }
        return weighted / total
    }

    // MARK: - Velocity

    @Test("A VEL amount moves a soft hit exactly as far as turning the knob down would")
    func velMatchesKnob() {
        let n0: Float = 0.6                                  // Vowel's position at a full hit
        let vowel = Self.index("vowel")
        let moved = hit(["velvowel": 60], velocity: 64) { brumle_set_normalised($0, Self.keyboard, vowel, n0) }
        let turned = hit(velocity: 64) {
            brumle_set_normalised($0, Self.keyboard, vowel, n0 - 0.6 * (1 - 64.0 / 127.0))
        }
        let unmoved = hit(velocity: 64) { brumle_set_normalised($0, Self.keyboard, vowel, n0) }
        let r = residualDb(moved, turned)
        #expect(r < -100, "residual \(r) dB")
        #expect(residualDb(moved, unmoved) > -40)            // and the amount did move it
    }

    @Test("A full-velocity hit ignores its VEL amounts")
    func velAtFull() {
        #expect(hit(["velring": 100], velocity: 127) == hit(velocity: 127))
    }

    @Test("VEL>Volume scales the level")
    func velVolume() {
        let soft = hit(["velsens": 0, "velvolume": 100], velocity: 64)
        let full = hit(["velsens": 0, "velvolume": 100], velocity: 127)
        let scaled = full.map { $0 * (64.0 / 127.0) }
        let r = residualDb(soft, scaled)
        #expect(r < -100, "residual \(r) dB")
    }

    // MARK: - LFOs

    /// Two hits `gap` seconds apart, each heard for the first second. Ring 0.3 s and the bus
    /// silent again (exactly 0) before the second hit, so that nothing of the first is left in it.
    /// LFO 1 moves the Vowel (a sine), LFO 2 the Close (Steps, which draws random levels).
    private func twoHits(start: Float, gap: Double) -> (first: ArraySlice<Float>, second: ArraySlice<Float>) {
        let engine = makeEngine(["ring": 0.3, "lfostart": start,
                                 "lfo1rate": 3, "lfo1vowel": 40,
                                 "lfo2rate": 5, "lfo2shape": 5, "lfo2close": 50])
        defer { brumle_destroy(engine) }
        let second = Self.frames(gap)
        brumle_midi(engine, 0x90, 36, 110, 0)
        var out = render(engine, frames: second)
        #expect(out[(second - 128)...].allSatisfy { $0 == 0 }, "the first hit is not silent yet")
        brumle_midi(engine, 0x90, 36, 110, 0)
        out += render(engine, seconds: 1)
        let one = Self.frames(1)
        return (out[0..<one], out[second..<(second + one)])
    }

    // 2.1 s and not 2 s apart: at 3 Hz, 2 s is a whole number of cycles, so a free-running LFO
    // would come round to the same phase and the two tests could not tell Hit from Free.
    @Test("With LFO Start = Hit every hit repeats exactly")
    func lfoHitRepeats() {
        let hits = twoHits(start: 0, gap: 2.1)
        #expect(Array(hits.first) == Array(hits.second))
    }

    @Test("With LFO Start = Free hits differ")
    func lfoFree() {
        let hits = twoHits(start: 1, gap: 2.1)
        let r = residualDb(hits.second, hits.first)
        #expect(r > -30, "residual \(r) dB")
    }

    @Test("An LFO amount moves the sound; amount 0 leaves it alone")
    func lfoAmount() {
        let still = hit()
        let moving = hit(["lfo1rate": 3, "lfo1vowel": 40])
        #expect(residualDb(moving, still) > -30)
        // Rates, shapes and the start do nothing while every amount is 0.
        let idle = hit(["lfo1rate": 20, "lfo1shape": 4, "lfo2rate": 0.1, "lfo2shape": 6, "lfostart": 1])
        #expect(idle == still)
    }

    // MARK: - Live knobs and wheels

    // With the vowel held still and the throat and the buzz turned down, the vowel resonance
    // carries the sound, which Close shuts. With the defaults it carries little of it 0.5 s into
    // a hit: the vowel has swept up to 1.8 kHz, and closing it then takes 0.3 dB off.
    @Test("A keyboard voice follows the knobs while it rings")
    func liveKnobs() {
        func play(closeAtHalf: Bool) -> [Float] {
            let engine = makeEngine(["sweep": 0, "throat": -30, "buzz": 0])
            defer { brumle_destroy(engine) }
            brumle_midi(engine, 0x90, 36, 110, 0)
            var out = render(engine, seconds: 0.5)
            if closeAtHalf { brumle_set_plain(engine, Self.keyboard, Self.index("close"), 100) }
            out += render(engine, seconds: 0.5)
            return out
        }
        let half = Self.frames(0.5)
        let open = play(closeAtHalf: false), closed = play(closeAtHalf: true)
        #expect(open[..<half] == closed[..<half])
        let drop = 20 * log10(rms(closed[half...]) / rms(open[half...]))
        #expect(drop < -6, "the next 0.5 s changed by \(drop) dB")
    }

    @Test("Pitch bend moves the vowel up")
    func bendMovesVowel() {
        let window = Self.frames(0.2)..<Self.frames(1.0)
        let level = hit(["sweep": 0])
        let bent = hit(["sweep": 0]) { brumle_midi($0, 0xE0, 0x7F, 0x7F, 0) }   // full up: +1
        let flat = spectralCentroid(level[window]), up = spectralCentroid(bent[window])
        #expect(up > flat * 1.1, "centroid \(flat) Hz -> \(up) Hz")
    }

    @Test("The mod wheel closes the mouth and aftertouch adds breath")
    func wheels() {
        // The mod wheel at the top adds the whole travel of Close: as Close at 100 %.
        let wheel = hit { brumle_midi($0, 0xB0, 1, 127, 0) }
        #expect(wheel == hit(["close": 100]))
        #expect(wheel != hit())
        // Full pressure adds +100 % of Breath: from 0 % to 100 %.
        let pressed = hit(["breath": 0]) { brumle_midi($0, 0xD0, 127, 0, 0) }
        #expect(pressed == hit(["breath": 100]))
        #expect(pressed != hit(["breath": 0]))
    }
}
