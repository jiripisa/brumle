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

    /// Taken on 2026-11-16 from the engine of phase 02 (the sound engine). A debug build and a
    /// release build rendered the same samples.
    private static let references: [Reference] = [
        Reference(score: "default phrase", sampleRate: 44100, fingerprint: 0x850B12AA838154, levels: [0.035967, 0.00315, 0.039354, 0.051396, 0.054573, 0.050979, 0.045164, 0.009028, 0.001041]),
        Reference(score: "default phrase", sampleRate: 48000, fingerprint: 0x59F6B133A08D2548, levels: [0.03597, 0.003145, 0.03942, 0.051431, 0.054636, 0.050981, 0.045125, 0.009037, 0.001049]),
        Reference(score: "default phrase", sampleRate: 96000, fingerprint: 0x27360D235B655121, levels: [0.03597, 0.003145, 0.039429, 0.051293, 0.05447, 0.050939, 0.045067, 0.009031, 0.001036]),
        Reference(score: "damped phrase", sampleRate: 44100, fingerprint: 0x5818B9C41B4B4F7C, levels: [0.035967, 0.00315, 0.040317, 0.06005, 0.065371, 0.06083, 0.058066, 0.012099, 0.001233]),
        Reference(score: "damped phrase", sampleRate: 48000, fingerprint: 0xABE6449773EBB7F7, levels: [0.03597, 0.003145, 0.040249, 0.059821, 0.065329, 0.060658, 0.058018, 0.012099, 0.001232]),
        Reference(score: "damped phrase", sampleRate: 96000, fingerprint: 0xC839D6E9730DAC51, levels: [0.03597, 0.003145, 0.040251, 0.059869, 0.065187, 0.06068, 0.057918, 0.012098, 0.001236]),
        Reference(score: "stroke in", sampleRate: 44100, fingerprint: 0x4865729062BE95FA, levels: [0.037461, 0.003164, 0.039792, 0.052069, 0.055282, 0.05179, 0.046176, 0.009002, 0.001048]),
        Reference(score: "stroke in", sampleRate: 48000, fingerprint: 0x38B952E40AB71896, levels: [0.037457, 0.003159, 0.03983, 0.052096, 0.055299, 0.05181, 0.04615, 0.009085, 0.001048]),
        Reference(score: "stroke in", sampleRate: 96000, fingerprint: 0xD1CB17CAF635042B, levels: [0.03746, 0.003121, 0.039832, 0.052202, 0.055437, 0.051949, 0.046298, 0.008918, 0.001052]),
        Reference(score: "stroke out", sampleRate: 44100, fingerprint: 0x31844E1E03652357, levels: [0.035967, 0.00315, 0.037855, 0.049121, 0.053063, 0.048571, 0.044548, 0.009028, 0.001041]),
        Reference(score: "stroke out", sampleRate: 48000, fingerprint: 0xABB80CF7F9098DDE, levels: [0.03597, 0.003145, 0.037901, 0.049045, 0.05305, 0.048565, 0.044544, 0.009037, 0.001049]),
        Reference(score: "stroke out", sampleRate: 96000, fingerprint: 0xB05F5AF58D35B517, levels: [0.03597, 0.003145, 0.03791, 0.04916, 0.053019, 0.04859, 0.044573, 0.009031, 0.001036]),
        Reference(score: "default kit groove", sampleRate: 44100, fingerprint: 0xB94E10323F7FE34A, levels: [0.074332, 0.095619, 0.087417, 0.087754, 0.078244, 0.083487, 0.089183, 0.089506, 0.077366, 0.058057, 0.034621, 0.009197]),
        Reference(score: "default kit groove", sampleRate: 48000, fingerprint: 0x29AF4B449E7079B8, levels: [0.07542, 0.095418, 0.08773, 0.088327, 0.078891, 0.084318, 0.089652, 0.088969, 0.077941, 0.058519, 0.033581, 0.00918]),
        Reference(score: "default kit groove", sampleRate: 96000, fingerprint: 0x12F5BDC255F11395, levels: [0.074551, 0.095348, 0.087499, 0.088055, 0.078143, 0.084057, 0.08894, 0.089097, 0.078398, 0.057826, 0.0341, 0.009614]),
        Reference(score: "pads, group off", sampleRate: 44100, fingerprint: 0xF2C76104EA97C804, levels: [0.043397, 0.044812, 0.004009, 0.00069]),
        Reference(score: "pads, group off", sampleRate: 48000, fingerprint: 0x776376C33B3A5DF5, levels: [0.043623, 0.04472, 0.004, 0.000668]),
        Reference(score: "pads, group off", sampleRate: 96000, fingerprint: 0x935735219506E8FA, levels: [0.04348, 0.044631, 0.004012, 0.000675]),
        Reference(score: "pads, one group", sampleRate: 44100, fingerprint: 0x8184BA55819385BC, levels: [0.043737, 0.042387, 0.000439, 0.0]),
        Reference(score: "pads, one group", sampleRate: 48000, fingerprint: 0x9848F350846DFFB5, levels: [0.043745, 0.042371, 0.000411, 0.0]),
        Reference(score: "pads, one group", sampleRate: 96000, fingerprint: 0xDEF1141D3302FD2C, levels: [0.04374, 0.042369, 0.000421, 0.0]),
        Reference(score: "lfo and vel", sampleRate: 44100, fingerprint: 0x6864EAE7FC351D3F, levels: [0.029848, 0.001355, 0.034552, 0.047546, 0.053238, 0.0458, 0.046038, 0.004965, 0.000508]),
        Reference(score: "lfo and vel", sampleRate: 48000, fingerprint: 0xC23752098714AD6D, levels: [0.029846, 0.001351, 0.034554, 0.047562, 0.053371, 0.045807, 0.046069, 0.004962, 0.000473]),
        Reference(score: "lfo and vel", sampleRate: 96000, fingerprint: 0xE55DAC0341704F6C, levels: [0.029846, 0.001354, 0.034554, 0.047626, 0.05281, 0.045738, 0.045903, 0.004961, 0.000488]),
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
