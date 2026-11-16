import AppKit
import AudioToolbox
import Foundation
import SwiftUI
import Testing
import BrumleAU
import BrumleDSP
import BrumleUI
@testable import BrumleAUView
@testable import BrumleCore

/// What a host's listener heard, in order. The listener runs on its own queue.
private final class Heard: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func add(_ event: String) { lock.withLock { events.append(event) } }
    var all: [String] { lock.withLock { events } }
}

/// The model behind the plug-in's window (`AudioUnitModel`), driving the real Audio Unit (`PlugIn`,
/// `Instrument`: AudioUnitTests.swift) the way the window's knobs, keys and pads and a host do.
@Suite("The plug-in's window")
@MainActor
struct AudioUnitWindowTests {

    private func model(of instrument: Instrument) throws -> AudioUnitModel {
        try #require(AudioUnitModel(unit: instrument.unit))
    }

    private func presentPreset(of unit: AudioUnit) throws -> Int {
        var preset = AUPreset()
        var size = UInt32(MemoryLayout<AUPreset>.size)
        try #require(AudioUnitGetProperty(unit, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0, &preset, &size) == noErr)
        preset.presetName?.release()
        return Int(preset.presetNumber)
    }

    /// Counts the unit's notices that its saved state changed, as a host listens for them to
    /// mark the project edited.
    private func countStateChanges(of unit: AudioUnit, _ body: (Calls) throws -> Void) throws {
        let calls = Calls()
        let listener: AudioUnitPropertyListenerProc = { refCon, _, id, scope, _ in
            guard id == kAudioUnitProperty_ClassInfo, scope == kAudioUnitScope_Global else { return }
            Unmanaged<Calls>.fromOpaque(refCon).takeUnretainedValue().count += 1
        }
        let refCon = Unmanaged.passUnretained(calls).toOpaque()
        try #require(AudioUnitAddPropertyListener(unit, kAudioUnitProperty_ClassInfo, listener, refCon) == noErr)
        defer { AudioUnitRemovePropertyListenerWithUserData(unit, kAudioUnitProperty_ClassInfo, listener, refCon) }
        try body(calls)
    }

    @Test("The window asks the unit by the numbers of BrumleAU.h")
    func propertyNumbers() {
        #expect(AudioUnitModel.engineProperty == AudioUnitPropertyID(kBrumleProperty_Engine))
        #expect(AudioUnitModel.stateChangedProperty == AudioUnitPropertyID(kBrumleProperty_StateChanged))
    }

    // MARK: The keyboard set: the unit's parameters

    @Test("Turning a knob of the keyboard sets the Audio Unit's parameter")
    func knobSetsParameter() throws {
        let instrument = try Instrument()
        let model = try model(of: instrument)
        let ring = try #require(Parameters.named("ring"))
        let stroke = try #require(Parameters.named("stroke"))

        model.setPosition(1, of: ring, in: .keyboard)
        let top = ring.plain(1)                                   // 15 s, to a few ulps
        #expect(abs(top - ring.range.upperBound) < 1e-4)
        #expect(try instrument.parameter(ring.index) == top)
        #expect(abs(model.position(of: ring, in: .keyboard) - 1) < 1e-6)

        model.setPosition(0.45, of: stroke, in: .keyboard)        // a choice snaps to its step
        let value = try instrument.parameter(stroke.index)
        #expect(value == value.rounded())
        #expect(model.value(of: stroke, in: .keyboard) == value)

        // The engine gets it at the next render, as from a host.
        let engine = try instrument.engine()
        _ = try instrument.render()
        #expect(abs(brumle_get_plain(engine, Int32(BRUMLE_KEYBOARD_SET), Int32(ring.index)) - top) < 1e-4)
    }

    @Test("A parameter or program the host changes shows in the window at the next refresh")
    func hostChangeShows() throws {
        let instrument = try Instrument()
        let model = try model(of: instrument)
        let vowel = try #require(Parameters.named("vowel"))
        let ring = try #require(Parameters.named("ring"))
        #expect(abs(model.value(of: vowel, in: .keyboard) - vowel.defaultValue) < 0.01)

        try instrument.setParameter("vowel", to: vowel.range.upperBound)
        model.refresh()
        #expect(model.position(of: vowel, in: .keyboard) == 1)

        try instrument.loadPreset(2)                          // the host's preset menu
        model.refresh()
        #expect(model.program(in: .keyboard) == 2)
        #expect(abs(model.value(of: ring, in: .keyboard) - Programs.value(program: 2, parameter: ring)) < 0.001)
    }

    @Test("Choosing a program loads the factory preset and leaves the octave alone")
    func choosingAProgram() throws {
        let instrument = try Instrument()
        let model = try model(of: instrument)
        let octave = try #require(Parameters.named("octave"))
        let ring = try #require(Parameters.named("ring"))
        model.setPosition(1, of: octave, in: .keyboard)        // +2

        model.loadProgram(3, into: .keyboard)                  // Morsing
        #expect(model.program(in: .keyboard) == 3)
        #expect(try presentPreset(of: instrument.unit) == 3)
        #expect(try instrument.parameter(ring.index) == Programs.value(program: 3, parameter: ring))
        #expect(abs(model.value(of: ring, in: .keyboard) - Programs.value(program: 3, parameter: ring)) < 0.001)
        #expect(try instrument.parameter(octave.index) == 2)

        // A double click goes back to the program's value.
        model.setPosition(1, of: ring, in: .keyboard)
        model.resetToDefault(ring, in: .keyboard)
        #expect(try instrument.parameter(ring.index) == Programs.value(program: 3, parameter: ring))
    }

    @Test("After a project is reopened, the window shows the keyboard's program the engine holds")
    func programShownAfterRestore() throws {
        let saved = try Instrument()
        try saved.loadPreset(3)
        try saved.setParameter("buzz", to: 55)                // the sound is no longer the preset's
        let state = try saved.classInfo()

        let reopened = try Instrument()
        let window = try model(of: reopened)                  // the window is open while the host restores
        try reopened.restore(state)
        #expect(try presentPreset(of: reopened.unit) == -1)   // the SDK forgets the number …
        window.refresh()
        #expect(window.program(in: .keyboard) == 3)            // … the engine does not
        #expect(window.padName(0) == PadLabel.name(program: window.program(in: .pad(0))))

        // A window opened afterwards shows it too, and a double click goes back to its value.
        let later = try model(of: reopened)
        #expect(later.program(in: .keyboard) == 3)
        let buzz = try #require(Parameters.named("buzz"))
        #expect(later.value(of: buzz, in: .keyboard) == 55)
        later.resetToDefault(buzz, in: .keyboard)
        #expect(try reopened.parameter(buzz.index) == Programs.value(program: 3, parameter: buzz))
    }

    /// A host's listener for one parameter. It runs on a queue of its own, so it is made outside
    /// the main actor.
    private nonisolated static func listen(to parameter: Parameter, of unit: AudioUnit, heard: Heard) throws -> AUEventListenerRef {
        var listener: AUEventListenerRef?
        try #require(AUEventListenerCreateWithDispatchQueue(&listener, 0, 0, DispatchQueue(label: "host")) { _, event, _, value in
            switch event.pointee.mEventType {
            case .beginParameterChangeGesture: heard.add("begin")
            case .endParameterChangeGesture: heard.add("end")
            case .parameterValueChange: heard.add("value \(Int(value))")
            default: break
            }
        } == noErr)
        let host = try #require(listener)
        let address = AudioUnitParameter(mAudioUnit: unit, mParameterID: AudioUnitParameterID(parameter.index),
                                         mScope: kAudioUnitScope_Global, mElement: 0)
        for type in [AudioUnitEventType.beginParameterChangeGesture, .parameterValueChange, .endParameterChangeGesture] {
            var event = AudioUnitEvent(mEventType: type, mArgument: .init(mParameter: address))
            try #require(AUEventListenerAddEventType(host, nil, &event) == noErr)
        }
        return host
    }

    @Test("A drag tells the host where it begins, what it sets and where it ends")
    func dragIsHeardByTheHost() async throws {
        let instrument = try Instrument()
        let model = try model(of: instrument)
        let buzz = try #require(Parameters.named("buzz"))

        // A host listens to the parameter the way it does to record automation.
        let heard = Heard()
        let host = try Self.listen(to: buzz, of: instrument.unit, heard: heard)
        defer { AUListenerDispose(host) }

        model.beginEditing(buzz, in: .keyboard)
        model.setPosition(0.5, of: buzz, in: .keyboard)
        model.endEditing(buzz, in: .keyboard)

        for _ in 0..<200 where heard.all.count < 3 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(heard.all == ["begin", "value 50", "end"])
    }

    // MARK: The pads: the engine

    @Test("Knobs, programs and resets in pad mode change the pad's set, never the unit's parameters")
    func padEditsStayInPad() throws {
        let instrument = try Instrument()
        let engine = try instrument.engine()
        let model = try model(of: instrument)
        let ring = try #require(Parameters.named("ring"))
        let buzz = try #require(Parameters.named("buzz"))
        let padSet = Int32(1 + 4)

        model.mode = .pads
        model.selectedPad = 4
        #expect(model.shownSet == .pad(4))
        #expect(brumle_get_mode(engine) == Int32(BRUMLE_MODE_PADS))

        model.setPosition(1, of: ring, in: .pad(4))
        model.loadProgram(5, into: .pad(4))                   // Bamboo
        model.setPosition(1, of: buzz, in: .pad(4))
        _ = try instrument.render()
        #expect(model.program(in: .pad(4)) == 5)
        #expect(model.padName(4) == "Bamboo")
        #expect(brumle_get_program(engine, padSet) == 5)
        #expect(brumle_get_plain(engine, padSet, Int32(buzz.index)) == buzz.range.upperBound)
        #expect(model.position(of: buzz, in: .pad(4)) == 1)

        model.resetToDefault(buzz, in: .pad(4))
        #expect(abs(brumle_get_plain(engine, padSet, Int32(buzz.index)) - Programs.value(program: 5, parameter: buzz)) < 0.001)

        // The keyboard set, the unit's parameters and its preset are as they were.
        for parameter in Parameters.all {
            #expect(try instrument.parameter(parameter.index) == parameter.defaultValue, "\(parameter.identifier)")
            #expect(model.position(of: parameter, in: .keyboard) == Double(parameter.normalised(parameter.defaultValue)))
        }
        #expect(model.program(in: .keyboard) == 0)
        #expect(try presentPreset(of: instrument.unit) == 0)

        // And the other way round: the keyboard's knobs leave the pad alone.
        let padRing = brumle_get_plain(engine, padSet, Int32(ring.index))
        model.setPosition(0, of: ring, in: .keyboard)
        model.loadProgram(2, into: .keyboard)
        _ = try instrument.render()
        #expect(brumle_get_plain(engine, padSet, Int32(ring.index)) == padRing)
        #expect(brumle_get_program(engine, padSet) == 5)
    }

    @Test("Pad notes, groups and the mode go to the engine and come back from it")
    func padNotesAndGroups() throws {
        let instrument = try Instrument()
        let engine = try instrument.engine()
        let model = try model(of: instrument)

        model.setPadNote(60, pad: 2)
        model.setPadGroup(7, pad: 2)
        model.setPadGroup(nil, pad: 3)
        #expect(brumle_pad_note(engine, 2) == 60)
        #expect(brumle_pad_group(engine, 2) == 7)
        #expect(brumle_pad_group(engine, 3) == 0)
        #expect(model.padNote(2) == 60)
        #expect(model.padGroup(2) == 7)
        #expect(model.padGroup(3) == nil)

        // What the host restores while the window is open shows at the next refresh.
        brumle_set_pad_note(engine, 9, 70)
        brumle_set_pad_group(engine, 9, 12)
        brumle_set_mode(engine, Int32(BRUMLE_MODE_PADS))
        model.refresh()
        #expect(model.padNote(9) == 70)
        #expect(model.padGroup(9) == 12)
        #expect(model.mode == .pads)
    }

    @Test("An edit of the pads or the mode marks the project edited, at most once per half second")
    func padEditsTellTheHost() throws {
        let instrument = try Instrument()
        let model = try model(of: instrument)
        let ring = try #require(Parameters.named("ring"))

        try countStateChanges(of: instrument.unit) { calls in
            // A drag edits many times; the host hears of it once, after it rests.
            for step in 0...20 { model.setPosition(Double(step) / 20, of: ring, in: .pad(1)) }
            model.refresh()
            #expect(calls.count == 0)
            model.tellHostIfEdited()                          // the window closes
            #expect(calls.count == 1)
            model.tellHostIfEdited()
            #expect(calls.count == 1)                         // nothing new

            // The keyboard's knobs are the unit's parameters: the host knows of them already.
            model.setPosition(0.3, of: ring, in: .keyboard)
            model.tellHostIfEdited()
            #expect(calls.count == 1)

            model.mode = .pads
            model.tellHostIfEdited()
            #expect(calls.count == 2)
        }
    }

    @Test("The host hears of a pad edit half a second after it, from the window's refresh")
    func padEditsTellTheHostLater() async throws {
        let instrument = try Instrument()
        let model = try model(of: instrument)

        try countStateChanges(of: instrument.unit) { calls in
            model.setPadNote(50, pad: 0)
            model.refresh()
            #expect(calls.count == 0)
        }
        try await Task.sleep(for: SaveDebounce.delay + .milliseconds(50))
        try countStateChanges(of: instrument.unit) { calls in
            model.refresh()
            #expect(calls.count == 1)
            model.refresh()
            #expect(calls.count == 1)
        }
    }

    // MARK: Playing on screen

    @Test("Send to pad from the window copies the keyboard's sound as the unit holds it, at the last note")
    func sendToPadFromWindow() throws {
        let instrument = try Instrument()
        let engine = try instrument.engine()
        let model = try model(of: instrument)
        let ring = try #require(Parameters.named("ring"))

        model.keyDown(55, velocity: 100)                      // the window's keyboard
        _ = try instrument.render()
        model.keyUp(55)
        model.refresh()
        #expect(model.lastNote == 55)

        model.loadProgram(5, into: .keyboard)
        model.setPosition(1, of: ring, in: .keyboard)         // not rendered yet: only the unit holds it
        model.sendToPad(6)

        let padSet = Int32(1 + 6)
        #expect(brumle_pad_note(engine, 6) == 55)
        #expect(brumle_get_program(engine, padSet) == 5)
        #expect(abs(brumle_get_plain(engine, padSet, Int32(ring.index)) - ring.range.upperBound) < 1e-4)
        #expect(model.padNote(6) == 55)
        #expect(model.program(in: .pad(6)) == 5)
        #expect(model.position(of: ring, in: .pad(6)) == 1)
    }

    @Test("A pad hit on screen plays the pad, selects it and counts")
    func padHitPlays() throws {
        let instrument = try Instrument()
        let model = try model(of: instrument)
        model.mode = .pads

        model.hitPad(3, velocity: 90)
        _ = try instrument.render()
        model.releasePad(3)
        model.refresh()
        #expect(model.selectedPad == 3)
        #expect(model.padHits(3) == 1)
        #expect(model.padHits(2) == 0)
    }

    @Test("Closing the window lets go of the keys it holds")
    func closingReleasesHeldKeys() throws {
        let instrument = try Instrument()
        let engine = try instrument.engine()
        let model = try model(of: instrument)
        let keyUp = try #require(Parameters.named("keyup"))
        model.setPosition(1, of: keyUp, in: .keyboard)        // Damp: a released key stops at once
        _ = try instrument.render()

        model.keyDown(50, velocity: 100)
        model.keyDown(57, velocity: 100)
        _ = try instrument.render()
        #expect(brumle_sounding_voices(engine) == 2)

        model.releaseHeld()                                   // the window goes away mid-press
        _ = try instrument.render()
        #expect(brumle_sounding_voices(engine) == 0)
    }

    // MARK: The window

    @Test("The window opens without the component's artwork, at the panel's width")
    func windowWithoutArt() throws {
        let instrument = try Instrument()
        let view = try #require(BrumleAUViewFactory().uiView(forAudioUnit: instrument.unit, with: .zero))
        // In the tests the factory's class lives in the test bundle, which holds no artwork.
        #expect(Artwork.bundle == Bundle(for: BrumleAUViewFactory.self))
        #expect(Artwork.background == nil)
        #expect(view.frame.width == InstrumentPanel<EmptyView, EmptyView>.width)
        #expect(view.frame.height > 400)
    }
}
