import Foundation
import Testing
import BrumleDSP
import BrumleReference
@testable import BrumleCore

/// One of the prototype's renders, as the engine plays it and as the prototype played it.
struct NamedScore: Sendable, CustomTestStringConvertible {
    let name: String
    let score: Score
    /// The prototype's values for the reference, as engine identifiers and plain engine values.
    let overrides: [String: Float]
    /// Puts the same sound into the engine's keyboard set.
    let apply: @Sendable (OpaquePointer) -> Void
    let keyUpDamp: Bool

    var testDescription: String { name }

    init(name: String, score: Score, overrides: [String: Float] = [:],
         apply: (@Sendable (OpaquePointer) -> Void)? = nil, keyUpDamp: Bool = false) {
        self.name = name
        self.score = score
        self.overrides = overrides
        self.apply = apply ?? { engine in
            for (key, value) in overrides {
                guard let index = Parameters.named(key)?.index else { preconditionFailure("unknown knob \(key)") }
                brumle_set_plain(engine, Int32(BRUMLE_KEYBOARD_SET), Int32(index), value)
            }
        }
        self.keyUpDamp = keyUpDamp
    }
}

/// Keyboard mode against the listening prototype the author approved: the engine renders the
/// prototype's scores at 96 kHz and must give the prototype's samples, up to one output scale.
@Suite("Prototype equivalence")
struct PrototypeEquivalenceTests {

    /// The engine's output scale against the prototype's raw sum: kLevel (0.2) times Volume
    /// -12 dB (10^(-12/20)).
    static let expectedScale = 0.2 * 0.251188643150958

    static let frames = 128

    // MARK: - Scores

    private static func phrase(_ name: String, note: UInt8 = 36, sub: Int = 2, chokeAhead: Double = 0,
                               _ overrides: [String: Float] = [:], keyUpDamp: Bool = false) -> NamedScore {
        NamedScore(name: name, score: PrototypeScores.phrase(note: note, sub: sub, chokeAhead: chokeAhead),
                   overrides: overrides, keyUpDamp: keyUpDamp)
    }

    private static func frame(_ seconds: Double) -> Int { Int((seconds * PrototypeScores.sampleRate).rounded()) }

    /// 11: eight hits on C2 0.7 s apart, from soft to full (brumle_spike.cpp:348-354).
    private static let velocityRamp: Score = {
        let hits = (0..<8).map { i in
            ScoreHit(frame: frame(0.2 + 0.7 * Double(i)), note: 36,
                     velocity: PrototypeScores.velocity(0.15 + 0.85 * Float(i) / 7), chokeOnly: false)
        }
        return Score(hits: hits, frames: frame(7.0))
    }()

    /// 12: C2 G2 D3 G3 C4, 1.6 s apart (brumle_spike.cpp:356-360).
    private static let range: Score = {
        let notes: [UInt8] = [36, 43, 50, 55, 60]
        let hits = notes.enumerated().map { i, note in
            ScoreHit(frame: frame(0.2 + 1.6 * Double(i)), note: note,
                     velocity: PrototypeScores.velocity(0.85), chokeOnly: false)
        }
        return Score(hits: hits, frames: frame(9.5))
    }()

    /// 13: a program as a phrase. `overrides` are the prototype's (brumle_spike.cpp:363-368)
    /// for the reference; the engine loads the program itself.
    private static func program(_ name: String, _ index: Int32, note: UInt8, _ overrides: [String: Float]) -> NamedScore {
        NamedScore(name: name, score: PrototypeScores.phrase(note: note), overrides: overrides,
                   apply: { brumle_set_program($0, Int32(BRUMLE_KEYBOARD_SET), index) })
    }

    /// The prototype's renders 01-12 and the six programs of 13 (brumle_spike.cpp:309-374).
    /// Left out as duplicates of 01 (the same phrase with the defaults): 02_B, 03_B, 04_B, 05_A,
    /// 06_B and 07_A. Left out as a duplicate of 09_A (16ths with the defaults): 10_B.
    static let keyboardScores: [NamedScore] = [
        phrase("01_default"),
        phrase("02_ring_A_1s_dry", ["ring": 1]),
        phrase("02_ring_C_7.5s_long", ["ring": 7.5]),
        phrase("03_edge_A_9_dark", ["edge": 9]),
        phrase("03_edge_C_30_bright", ["edge": 30]),
        phrase("04_parity_A_bare_odd", ["offset": 0, "breath": 0, "puff": 0]),
        phrase("04_parity_C_inhale", ["breath": -30]),
        phrase("05_body_B_-10dB_more_fundamental", ["body": -10]),
        phrase("06_tone_A_twang_spring", ["reso": 8, "buzz": 80]),
        phrase("06_tone_C_whistle", ["reso": 30, "buzz": 0]),
        phrase("07_gesture_B_up_80ms_fast", ["sweeptime": 80]),
        phrase("07_gesture_C_up_320ms_slow", ["sweeptime": 320]),
        phrase("07_gesture_D_down", ["vowel": 1800, "sweep": -14]),
        phrase("07_gesture_E_there_and_back", ["curve": 2, "sweeptime": 300]),
        phrase("07_gesture_F_none", ["sweep": 0, "vowel": 1100]),
        phrase("08_clang_A_none", ["clang": 0]),
        phrase("08_clang_B_strong", ["clang": 60]),
        phrase("09_restrike_A_choke_10ms_at_stroke", sub: 4),
        phrase("09_restrike_B_choke_40ms_at_stroke", sub: 4, ["damp": 40]),
        phrase("09_restrike_C_choke_40ms_before_stroke", sub: 4, chokeAhead: 0.040, keyUpDamp: true),
        phrase("10_vary_A_0", sub: 4, ["vary": 0]),
        phrase("10_vary_C_50", sub: 4, ["vary": 50]),
        NamedScore(name: "11_velocity_A_brightness_and_breath", score: velocityRamp),
        // The prototype's "level only" velocity is Vel Sens 0 with VEL>Volume 100 %.
        NamedScore(name: "11_velocity_B_level_only", score: velocityRamp, overrides: ["levelOnly": 1],
                   apply: { engine in
                       brumle_set_plain(engine, Int32(BRUMLE_KEYBOARD_SET), Int32(Parameters.named("velsens")!.index), 0)
                       brumle_set_plain(engine, Int32(BRUMLE_KEYBOARD_SET), Int32(Parameters.named("velvolume")!.index), 100)
                   }),
        NamedScore(name: "12_range_C2_G2_D3_G3_C4", score: range),
        program("13_program_Molln", 1, note: 36,
                ["ring": 7.5, "sweep": 0, "vowel": 1050, "reso": 25, "open": 0, "offset": 0]),
        program("13_program_Khomus", 2, note: 38,
                ["ring": 8, "edge": 26, "buzz": 70, "curve": 2, "sweep": 12, "sweeptime": 400]),
        program("13_program_Morsing", 3, note: 48,
                ["ring": 1, "edge": 26, "sweeptime": 60, "puff": 80, "close": 40, "damp": 5]),
        program("13_program_DanMoi", 4, note: 39,
                ["clang": 0, "open": 60, "air": 30, "reso": 10, "ring": 3, "stroke": 0]),
        program("13_program_Bamboo", 5, note: 38,
                ["ring": 1, "edge": 7, "clang": 60, "buzz": 15, "reso": 8]),
        program("13_program_Genggong", 6, note: 41,
                ["ring": 0.8, "edge": 9, "clang": 40, "open": 100]),
    ]

    // MARK: - Rendering and comparing

    /// Renders `score` in keyboard mode at 96 kHz, in blocks of 128 frames, each block's hits
    /// given with `brumle_midi` before it is processed. A hit is a note-on and a choke-only hit
    /// a note-off.
    func engineRender(_ score: Score, set: (OpaquePointer) -> Void, keyUpDamp: Bool) -> (left: [Float], right: [Float]) {
        let engine = brumle_create()!
        defer { brumle_destroy(engine) }
        brumle_prepare(engine, PrototypeScores.sampleRate)
        brumle_reset(engine)
        brumle_set_mode(engine, Int32(BRUMLE_MODE_KEYBOARD))
        set(engine)
        let keyboard = Int32(BRUMLE_KEYBOARD_SET)
        brumle_set_plain(engine, keyboard, Int32(Parameters.named("volume")!.index), -12)   // keeps the peaks under 0.6
        if keyUpDamp { brumle_set_plain(engine, keyboard, Int32(Parameters.named("keyup")!.index), 1) }

        var left = [Float](repeating: 0, count: score.frames)
        var right = [Float](repeating: 0, count: score.frames)
        var next = 0
        var start = 0
        while start < score.frames {
            let count = min(Self.frames, score.frames - start)
            while next < score.hits.count && score.hits[next].frame < start + count {
                let hit = score.hits[next]
                let offset = Int32(hit.frame - start)
                if hit.chokeOnly { brumle_midi(engine, 0x80, Int32(hit.note), 0, offset) }
                else { brumle_midi(engine, 0x90, Int32(hit.note), Int32(hit.velocity), offset) }
                next += 1
            }
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    brumle_process(engine, l.baseAddress! + start, r.baseAddress! + start, Int32(count))
                }
            }
            start += count
        }
        return (left, right)
    }

    /// The least-squares scale of `reference` onto `engine` (<e,r>/<r,r>), and what is left of
    /// the engine's output after it, in dB re the scaled reference.
    func matches(_ engine: [Float], _ reference: [Float]) -> (scale: Double, residualDb: Double) {
        precondition(engine.count == reference.count)
        var er = 0.0, rr = 0.0
        for i in engine.indices { er += Double(engine[i]) * Double(reference[i]); rr += Double(reference[i]) * Double(reference[i]) }
        let scale = er / rr
        var residual = 0.0, signal = 0.0
        for i in engine.indices {
            let s = scale * Double(reference[i])
            residual += (Double(engine[i]) - s) * (Double(engine[i]) - s)
            signal += s * s
        }
        return (scale, 10 * log10(residual / signal))
    }

    // MARK: - Tests

    @Test("Keyboard mode plays the approved prototype scores", arguments: PrototypeEquivalenceTests.keyboardScores)
    func keyboardScore(_ s: NamedScore) {
        let ref = PrototypeScores.referenceRender(s.score, params: [PrototypeScores.referenceParams(s.overrides)]) { _ in 0 }
        let out = engineRender(s.score, set: s.apply, keyUpDamp: s.keyUpDamp)
        #expect(out.left == out.right)                                   // Pan at the centre
        #expect((out.left.map(abs).max() ?? 0) < 0.6)                    // the limiter stays out of it
        let m = matches(out.left, ref)
        #expect(m.residualDb < -60, "\(s.name): residual \(m.residualDb) dB")
        #expect(abs(m.scale - Self.expectedScale) / Self.expectedScale < 1e-3)   // one output scale for all
    }
}
