import Testing
@testable import BrumleCore

/// Guards the sound itself: the references below were taken from the engine, so a change in
/// `BrumleDSP` that alters a single sample fails here.
///
/// Each reference holds two things: a fingerprint of every sample, and the level of each second.
/// They tell two cases apart:
/// - levels differ: the sound really changed;
/// - only fingerprints differ, for every score at once and without a change in the engine: a new
///   compiler or macOS rounds differently.
///
/// When a change of the sound is deliberate, say so in the CHANGELOG, run the suite and copy the
/// lines it prints over `references`.
@Suite("Sound")
struct SoundRegressionTests {

    private struct Case {
        let name: String
        let mode: PlayMode
        let setup: @Sendable (Synth) -> Void
        let events: [GrooveEvent]
        let duration: Double
    }

    /// The prototype's phrase, in seconds, as MIDI events (a stop of the ringing reed is a note-off).
    private static func phrase(_ score: Score) -> [GrooveEvent] {
        score.hits.map {
            GrooveEvent(Double($0.frame) / PrototypeScores.sampleRate, $0.chokeOnly ? 0x80 : 0x90, $0.note,
                        $0.chokeOnly ? 0 : $0.velocity)
        }
    }

    private static let phraseLength = PrototypeScores.phraseLength

    /// Two pads on one pitch, hit in turn.
    private static let pairEvents: [GrooveEvent] = [
        GrooveEvent(0.2, 0x90, 36, 110), GrooveEvent(0.7, 0x90, 37, 100),
        GrooveEvent(1.2, 0x90, 36, 110), GrooveEvent(1.7, 0x90, 37, 100),
    ]

    private static func setUpPair(group: Int?) -> @Sendable (Synth) -> Void {
        { synth in
            for pad in [0, 1] { synth.setPadNote(40, pad: pad); synth.setPadGroup(group, pad: pad) }
        }
    }

    private static func set(_ identifier: String, _ value: Float) -> @Sendable (Synth) -> Void {
        { synth in synth.setValue(value, of: Parameters.named(identifier)!) }
    }

    private static let scores: [Case] = [
        Case(name: "default phrase", mode: .keyboard, setup: { _ in },
              events: phrase(PrototypeScores.phrase(note: 36)), duration: phraseLength),
        Case(name: "damped phrase", mode: .keyboard, setup: { _ in },
              events: phrase(PrototypeScores.phrase(note: 36, sub: 4, chokeAhead: 0.040)), duration: phraseLength),
        Case(name: "stroke in", mode: .keyboard, setup: set("stroke", 1),
              events: phrase(PrototypeScores.phrase(note: 36)), duration: phraseLength),
        Case(name: "stroke out", mode: .keyboard, setup: set("stroke", 0),
              events: phrase(PrototypeScores.phrase(note: 36)), duration: phraseLength),
        Case(name: "default kit groove", mode: .pads, setup: { _ in },
              events: Grooves.defaultKit, duration: Grooves.defaultKitLength),
        Case(name: "pads, group off", mode: .pads, setup: setUpPair(group: nil),
              events: pairEvents, duration: 3.5),
        Case(name: "pads, one group", mode: .pads, setup: setUpPair(group: 1),
              events: pairEvents, duration: 3.5),
        Case(name: "lfo and vel", mode: .keyboard,
              setup: { synth in
                  synth.setValue(40, of: Parameters.named("lfo1vowel")!)
                  synth.setValue(50, of: Parameters.named("velring")!)
              },
              events: phrase(PrototypeScores.phrase(note: 36, sub: 4)), duration: phraseLength),
    ]
    private static let rates = [44_100.0, 48_000.0, 96_000.0]
    private static let blockSize = 128

    private struct Reference {
        let score: String
        let sampleRate: Double
        /// FNV-1a over the bits of every sample.
        let fingerprint: UInt64
        /// RMS of each second (the last one is shorter).
        let levels: [Double]

        /// This reference as a line of `references`.
        var sourceLine: String {
            let levelList = levels.map { "\(($0 * 1_000_000).rounded() / 1_000_000)" }.joined(separator: ", ")
            return "Reference(score: \"\(score)\", sampleRate: \(Int(sampleRate)), "
                + "fingerprint: 0x\(String(fingerprint, radix: 16, uppercase: true)), levels: [\(levelList)]),"
        }
    }

    /// Taken on 2026-11-16 from the engine of phase 02 (the sound engine), and taken again the same
    /// day when Air and the breath were made to fade with the reed (the tails had hissed). A debug
    /// build and a release build rendered the same samples.
    private static let references: [Reference] = [
        Reference(score: "default phrase", sampleRate: 44100, fingerprint: 0x201F5E42E15E80D7, levels: [0.035967, 0.003146, 0.039354, 0.051395, 0.054571, 0.050977, 0.045163, 0.009028, 0.001015]),
        Reference(score: "default phrase", sampleRate: 48000, fingerprint: 0x121A252046361A64, levels: [0.03597, 0.003141, 0.039423, 0.051429, 0.054631, 0.050977, 0.045124, 0.009037, 0.001024]),
        Reference(score: "default phrase", sampleRate: 96000, fingerprint: 0x4B4B4F989C17319C, levels: [0.03597, 0.003141, 0.039431, 0.051289, 0.054468, 0.050937, 0.045067, 0.009031, 0.001009]),
        Reference(score: "damped phrase", sampleRate: 44100, fingerprint: 0x12115195DD6E5469, levels: [0.035967, 0.003146, 0.040315, 0.060045, 0.065367, 0.060826, 0.058061, 0.012099, 0.001222]),
        Reference(score: "damped phrase", sampleRate: 48000, fingerprint: 0xFB69C6CC45F6C6C2, levels: [0.03597, 0.003141, 0.040248, 0.059817, 0.065326, 0.060654, 0.058016, 0.012099, 0.001222]),
        Reference(score: "damped phrase", sampleRate: 96000, fingerprint: 0x15A461AB43325EA8, levels: [0.03597, 0.003141, 0.04025, 0.059866, 0.065184, 0.060677, 0.057915, 0.012098, 0.001225]),
        Reference(score: "stroke in", sampleRate: 44100, fingerprint: 0xDABC45ACFCDF1BA6, levels: [0.037461, 0.00316, 0.039791, 0.052066, 0.055276, 0.051784, 0.04617, 0.009002, 0.001021]),
        Reference(score: "stroke in", sampleRate: 48000, fingerprint: 0xD2C943BC7A5284BC, levels: [0.037457, 0.003155, 0.039828, 0.052091, 0.055292, 0.051803, 0.046145, 0.009085, 0.001023]),
        Reference(score: "stroke in", sampleRate: 96000, fingerprint: 0xD4D0D9E4209EB85F, levels: [0.03746, 0.003117, 0.039829, 0.052197, 0.055431, 0.051941, 0.046293, 0.008918, 0.001025]),
        Reference(score: "stroke out", sampleRate: 44100, fingerprint: 0xE0C3399BDF47B72A, levels: [0.035967, 0.003146, 0.037854, 0.049124, 0.053069, 0.048576, 0.044552, 0.009028, 0.001015]),
        Reference(score: "stroke out", sampleRate: 48000, fingerprint: 0x74F595CB2C3ACBFB, levels: [0.03597, 0.003141, 0.037902, 0.049049, 0.053053, 0.048571, 0.044547, 0.009037, 0.001024]),
        Reference(score: "stroke out", sampleRate: 96000, fingerprint: 0x39648A589FD219E2, levels: [0.03597, 0.003141, 0.037911, 0.049165, 0.053023, 0.048594, 0.044575, 0.009031, 0.001009]),
        Reference(score: "default kit groove", sampleRate: 44100, fingerprint: 0x9BAECA16AA5BFD03, levels: [0.074332, 0.095616, 0.087405, 0.087756, 0.078232, 0.083477, 0.089177, 0.089497, 0.077371, 0.058054, 0.034587, 0.009063]),
        Reference(score: "default kit groove", sampleRate: 48000, fingerprint: 0xF8C7F1941F8A9A1A, levels: [0.07542, 0.095424, 0.087713, 0.088331, 0.078876, 0.084316, 0.089646, 0.088965, 0.077939, 0.05851, 0.033539, 0.009065]),
        Reference(score: "default kit groove", sampleRate: 96000, fingerprint: 0x56A1351A72603567, levels: [0.074551, 0.095354, 0.087479, 0.088058, 0.078131, 0.084047, 0.088934, 0.0891, 0.078391, 0.057824, 0.034063, 0.009505]),
        Reference(score: "pads, group off", sampleRate: 44100, fingerprint: 0x75DE1704A4E149C8, levels: [0.043397, 0.04482, 0.003988, 0.000543]),
        Reference(score: "pads, group off", sampleRate: 48000, fingerprint: 0x7BB0B19F97D85BF7, levels: [0.043623, 0.044719, 0.00398, 0.000536]),
        Reference(score: "pads, group off", sampleRate: 96000, fingerprint: 0x9B906AA7C2F09092, levels: [0.04348, 0.04463, 0.003986, 0.000536]),
        Reference(score: "pads, one group", sampleRate: 44100, fingerprint: 0x38D115C43EA47D77, levels: [0.043737, 0.042389, 0.00015, 0.0]),
        Reference(score: "pads, one group", sampleRate: 48000, fingerprint: 0x707CB3DE5DA2B111, levels: [0.043745, 0.042372, 0.000149, 0.0]),
        Reference(score: "pads, one group", sampleRate: 96000, fingerprint: 0x570E47BF5006BBAC, levels: [0.043741, 0.042369, 0.000148, 0.0]),
        Reference(score: "lfo and vel", sampleRate: 44100, fingerprint: 0xE47715F11EB6D888, levels: [0.029848, 0.001314, 0.034547, 0.047542, 0.053233, 0.045799, 0.046032, 0.004956, 5.7e-05]),
        Reference(score: "lfo and vel", sampleRate: 48000, fingerprint: 0x935FCCA2C20F2A85, levels: [0.029846, 0.001312, 0.034552, 0.047561, 0.05337, 0.045805, 0.046071, 0.004952, 5.6e-05]),
        Reference(score: "lfo and vel", sampleRate: 96000, fingerprint: 0x2AFDF326C8FCC552, levels: [0.029846, 0.001313, 0.034552, 0.047626, 0.052808, 0.045735, 0.0459, 0.004951, 5.6e-05]),
    ]

    private static func render(_ score: Case, sampleRate: Double) -> [Float] {
        let synth = Synth(sampleRate: sampleRate)
        synth.mode = score.mode
        score.setup(synth)
        let blocks = Int(score.duration * sampleRate) / blockSize
        var samples: [Float] = []
        samples.reserveCapacity(blocks * blockSize)
        var left = [Float](repeating: 0, count: blockSize)
        var right = [Float](repeating: 0, count: blockSize)
        var next = 0
        for block in 0..<blocks {
            let time = Double(block * blockSize) / sampleRate
            while next < score.events.count, score.events[next].time <= time {
                let event = score.events[next]
                synth.postMIDI(status: event.status, data1: event.data1, data2: event.data2)
                next += 1
            }
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    synth.render(left: l.baseAddress!, right: r.baseAddress!, frames: blockSize)
                }
            }
            samples.append(contentsOf: left)
        }
        return samples
    }

    private static func fingerprint(of samples: [Float]) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for sample in samples {
            var bits = sample.bitPattern
            for _ in 0..<4 {
                hash = (hash ^ UInt64(bits & 0xFF)) &* 0x0000_0100_0000_01B3
                bits >>= 8
            }
        }
        return hash
    }

    private static func levels(of samples: [Float], sampleRate: Double) -> [Double] {
        let second = Int(sampleRate)
        return stride(from: 0, to: samples.count, by: second).map { start in
            let window = samples[start..<min(start + second, samples.count)]
            let energy = window.reduce(0.0) { $0 + Double($1) * Double($1) }
            return (energy / Double(window.count)).squareRoot()
        }
    }

    @Test("Every score sounds as it did when its reference was taken",
          arguments: SoundRegressionTests.scores.map(\.name), SoundRegressionTests.rates)
    func unchanged(name: String, sampleRate: Double) throws {
        let score = try #require(Self.scores.first { $0.name == name })
        let samples = Self.render(score, sampleRate: sampleRate)
        #expect(samples.allSatisfy { $0.isFinite })
        let actual = Reference(score: name, sampleRate: sampleRate,
                               fingerprint: Self.fingerprint(of: samples),
                               levels: Self.levels(of: samples, sampleRate: sampleRate))
        let expected = try #require(Self.references.first { $0.score == name && $0.sampleRate == sampleRate },
                                    "no reference yet; add: \(actual.sourceLine)")

        try #require(actual.levels.count == expected.levels.count)
        for (second, (level, reference)) in zip(actual.levels, expected.levels).enumerated() {
            #expect(abs(level - reference) <= max(reference * 0.001, 0.000_001),
                    "\(name) at \(Int(sampleRate)) Hz: the level of second \(second) changed from \(reference) to \(level)")
        }
        #expect(actual.fingerprint == expected.fingerprint,
                "\(name) at \(Int(sampleRate)) Hz no longer renders the same samples; now: \(actual.sourceLine)")
    }
}
