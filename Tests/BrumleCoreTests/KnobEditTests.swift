import Observation
import Testing
import BrumleCore
@testable import BrumleUI

/// A drag on a knob of the panel as the edit a host records.
@Suite("Knob edit")
@MainActor
struct KnobEditTests {

    /// Records what the panel asks of the model; positions live in a dictionary.
    @Observable
    final class Recorder: InstrumentModel {
        enum Call: Equatable {
            case begin(String, SoundSet), end(String, SoundSet), reset(String, SoundSet)
        }
        var calls: [Call] = []
        var positions: [String: Double] = [:]
        var mode: PlayMode = .keyboard
        var selectedPad = 0
        var shownSet: SoundSet { mode == .keyboard ? .keyboard : .pad(selectedPad) }

        func program(in set: SoundSet) -> Int { 0 }
        func loadProgram(_ index: Int, into set: SoundSet) {}
        func position(of parameter: Parameter, in set: SoundSet) -> Double { positions[parameter.identifier] ?? 0.5 }
        func setPosition(_ position: Double, of parameter: Parameter, in set: SoundSet) { positions[parameter.identifier] = position }
        func resetToDefault(_ parameter: Parameter, in set: SoundSet) { calls.append(.reset(parameter.identifier, set)) }
        func beginEditing(_ parameter: Parameter, in set: SoundSet) { calls.append(.begin(parameter.identifier, set)) }
        func endEditing(_ parameter: Parameter, in set: SoundSet) { calls.append(.end(parameter.identifier, set)) }
        func padNote(_ pad: Int) -> Int { 36 + pad }
        func setPadNote(_ note: Int, pad: Int) {}
        func padGroup(_ pad: Int) -> Int? { nil }
        func setPadGroup(_ group: Int?, pad: Int) {}
        func padName(_ pad: Int) -> String { "" }
        func padHits(_ pad: Int) -> Int { 0 }
        var lastNote: Int? { nil }
        func sendToPad(_ pad: Int) {}
        func hitPad(_ pad: Int, velocity: Int) {}
        func releasePad(_ pad: Int) {}
        func keyDown(_ note: Int, velocity: Int) {}
        func keyUp(_ note: Int) {}
        func refresh() {}
    }

    private let ring = Parameters.named("ring")!
    private let amount = Parameters.named("lfo1vowel")!

    @Test("A drag begins one edit and ends it, in the set it began in")
    func beginAndEndPair() {
        let model = Recorder()
        model.mode = .pads
        model.selectedPad = 3
        var edit = KnobEdit.begin(ring, in: model.shownSet, isAmount: false, model: model)
        edit.move(to: 10, fine: false, model: model)
        model.selectedPad = 7                     // MIDI selects another pad mid-drag
        edit.move(to: 20, fine: false, model: model)
        edit.end(model: model)
        #expect(model.calls == [.begin("ring", .pad(3)), .end("ring", .pad(3))])
    }

    @Test("Up turns the knob up; 200 points turn it end to end, and no further")
    func travel() {
        let model = Recorder()
        var edit = KnobEdit.begin(ring, in: .keyboard, isAmount: false, model: model)
        edit.move(to: -50, fine: false, model: model)
        #expect(model.positions["ring"] == 0.75)
        edit.move(to: -500, fine: false, model: model)
        #expect(model.positions["ring"] == 1)
        edit.move(to: -450, fine: false, model: model)
        #expect(model.positions["ring"] == 0.75)
    }

    @Test("Shift pressed halfway makes the rest of the drag finer, without a jump")
    func shiftHalfway() {
        let model = Recorder()
        var edit = KnobEdit.begin(ring, in: .keyboard, isAmount: false, model: model)
        edit.move(to: -50, fine: false, model: model)
        #expect(model.positions["ring"] == 0.75)
        edit.move(to: -50, fine: true, model: model)
        #expect(model.positions["ring"] == 0.75)
        edit.move(to: -100, fine: true, model: model)
        #expect(abs(model.positions["ring"]! - 0.775) < 1e-12)
        edit.move(to: -100, fine: false, model: model)
        #expect(abs(model.positions["ring"]! - 0.775) < 1e-12)
    }

    @Test("An amount close to nothing is nothing, and the drag goes on past it")
    func amountSnaps() {
        let model = Recorder()
        var edit = KnobEdit.begin(amount, in: .keyboard, isAmount: true, model: model)   // at 0 %
        edit.move(to: -1, fine: false, model: model)                                      // +1 % ...
        edit.move(to: -0.5, fine: false, model: model)                                    // ... back to +0.5 %
        #expect(model.positions["lfo1vowel"] == Double(amount.normalised(0)))
        edit.move(to: -3, fine: false, model: model)                                      // +3 %
        #expect(abs(Double(amount.plain(Float(model.positions["lfo1vowel"]!))) - 3) < 1e-3)
    }

    @Test("A double click puts the value back as an edit of its own")
    func resetIsAnEdit() {
        let model = Recorder()
        KnobEdit.reset(ring, in: .pad(2), model: model)
        #expect(model.calls == [.begin("ring", .pad(2)), .reset("ring", .pad(2)), .end("ring", .pad(2))])
    }
}
