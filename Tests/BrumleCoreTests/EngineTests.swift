import Foundation
import Testing
import BrumleDSP
@testable import BrumleCore

/// What the sound engine promises beyond matching the prototype: its level, how it chokes and
/// stops, and how its C interface copes with what callers hand it.
@Suite("Engine")
struct EngineTests {

    static let rate = 96_000.0
    static let keyboard = Int32(BRUMLE_KEYBOARD_SET)

    private static func index(_ identifier: String) -> Int32 { Int32(Parameters.named(identifier)!.index) }

    /// A fresh engine at 96 kHz in keyboard mode, with `knobs` (plain values) in the keyboard set.
    private func makeEngine(_ knobs: [String: Float] = [:]) -> OpaquePointer {
        let engine = brumle_create()!
        brumle_prepare(engine, Self.rate)
        brumle_reset(engine)
        brumle_set_mode(engine, Int32(BRUMLE_MODE_KEYBOARD))
        for (key, value) in knobs { brumle_set_plain(engine, Self.keyboard, Self.index(key), value) }
        return engine
    }

    /// Renders `seconds` of the left channel in blocks of 128 frames.
    private func render(_ engine: OpaquePointer, seconds: Double) -> [Float] {
        render(engine, frames: Int((seconds * Self.rate).rounded()))
    }

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

    private func rms<C: Collection>(_ x: C) -> Double where C.Element == Float {
        (x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(x.count, 1))).squareRoot()
    }

    /// dB of (a - b) re b.
    private func residualDb(_ a: ArraySlice<Float>, _ b: ArraySlice<Float>) -> Double {
        var difference = 0.0, signal = 0.0
        for (x, y) in zip(a, b) { difference += Double(x - y) * Double(x - y); signal += Double(y) * Double(y) }
        return 10 * log10(difference / signal)
    }

    private static let plain: [String: Float] = ["stroke": 0, "vary": 0, "air": 0]   // Out, no randomness

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
        brumle_set_pad_group(engine, 0, 17)
        #expect(brumle_pad_group(engine, 0) == 0)
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
}
