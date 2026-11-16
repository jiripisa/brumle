import Testing
import BrumleDSP
@testable import BrumleCore

/// The Swift wrapper only forwards to the engine: what is set is what is read back, on the right set.
@Suite("Synth")
struct SynthTests {

    private func render(_ synth: Synth, frames: Int = 4_096) -> [Float] {
        var out = [Float](repeating: 0, count: frames)
        out.withUnsafeMutableBufferPointer { synth.render(left: $0.baseAddress!, right: nil, frames: frames) }
        return out
    }

    @Test("A value round-trips, plain and normalised, in the keyboard set and in a pad")
    func valuesRoundTrip() throws {
        let synth = Synth(sampleRate: 48_000)
        let vowel = try #require(Parameters.named("vowel"))
        for set in [SoundSet.keyboard, .pad(0), .pad(15)] {
            synth.setValue(900, of: vowel, in: set)
            #expect(abs(synth.value(of: vowel, in: set) - 900) < 0.5)
            synth.setNormalisedValue(0.25, of: vowel, in: set)
            #expect(abs(synth.normalisedValue(of: vowel, in: set) - 0.25) < 1e-5)
        }
        synth.setValue(vowel.range.lowerBound, of: vowel, in: .pad(3))
        #expect(synth.value(of: vowel, in: .keyboard) != synth.value(of: vowel, in: .pad(3)))
        #expect(SoundSet.keyboard.index == 0 && SoundSet.pad(0).index == 1 && SoundSet.pad(15).index == 16)
    }

    @Test("A program loads into its own set")
    func programs() {
        let synth = Synth()
        synth.loadProgram(2, into: .pad(4))
        synth.loadProgram(1)
        #expect(synth.program(in: .pad(4)) == 2)
        #expect(synth.program(in: .keyboard) == 1)
    }

    @Test("The mode, a pad's note and its group round-trip; Off reads back as nil")
    func modeAndPads() {
        let synth = Synth()
        #expect(synth.mode == .keyboard)
        synth.mode = .pads
        #expect(synth.mode == .pads)
        synth.setPadNote(50, pad: 7)
        #expect(synth.padNote(7) == 50)
        synth.setPadGroup(3, pad: 7)
        #expect(synth.padGroup(7) == 3)
        synth.setPadGroup(nil, pad: 7)
        #expect(synth.padGroup(7) == nil)
    }

    @Test("Send to pad copies the last note; the kit loads on demand")
    func sendToPad() {
        let synth = Synth()
        #expect(synth.lastNote == nil)
        synth.noteOn(52)
        _ = render(synth)
        #expect(synth.lastNote == 52)
        synth.sendToPad(9)
        #expect(synth.padNote(9) == 52)
        synth.loadDefaultKit()
        #expect(synth.padNote(9) != 52)
    }

    @Test("Notes above 127 clamp; velocity 0 sounds as velocity 1")
    func clamping() {
        let high = Synth()
        high.noteOn(200)
        _ = render(high)
        #expect(high.lastNote == 127)

        func hit(velocity: Int) -> [Float] {
            let synth = Synth()
            synth.noteOn(60, velocity: velocity)
            return render(synth)
        }
        let silent = hit(velocity: 0)
        #expect(silent == hit(velocity: 1))
        #expect(silent.contains { $0 != 0 })
    }

    @Test("Voices count while sounding and stop after all notes off; the latency is the engine's")
    func voicesAndLatency() {
        let synth = Synth(sampleRate: 48_000)
        #expect(synth.latency == Int(brumle_latency(synth.engine)) && synth.latency > 0)
        synth.noteOn(48)
        synth.noteOn(55)
        _ = render(synth, frames: 512)
        #expect(synth.soundingVoices == 2)
        synth.allNotesOff()
        _ = render(synth, frames: 512)
        #expect(synth.soundingVoices == 0)
        synth.prepare(sampleRate: 96_000)
        #expect(synth.latency == 0)
    }
}
