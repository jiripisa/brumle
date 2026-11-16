import BrumleCore
import Observation

/// What the panel needs from whoever owns the sound: the standalone app's
/// model, or the plug-in's, which talks to the Audio Unit in a host. Both are
/// observable, so the panel follows their changes.
///
/// The sound is in sets of knobs: the keyboard's and one for each of the
/// sixteen pads (`SoundSet`). The panel shows one of them, `shownSet`.
@MainActor
public protocol InstrumentModel: AnyObject, Observable {

    /// What the keyboard plays: the keyboard's sound, or the pads (notes 36–51).
    var mode: PlayMode { get set }

    /// The pad the panel edits in pad mode, 0...15.
    var selectedPad: Int { get set }

    /// The set the knobs show and edit: the keyboard's in keyboard mode, the
    /// selected pad's (`.pad(selectedPad)`) in pad mode.
    var shownSet: SoundSet { get }

    /// The built-in program a set last loaded. Outside `Programs.names` when
    /// its sound did not come from one (a host's own preset).
    func program(in set: SoundSet) -> Int

    /// Loads a built-in program into a set: every knob but the octave.
    func loadProgram(_ index: Int, into set: SoundSet)

    /// Knob position (0...1) of a parameter in a set.
    func position(of parameter: Parameter, in set: SoundSet) -> Double

    /// Turns a knob. Integers and choices snap to their steps.
    func setPosition(_ position: Double, of parameter: Parameter, in set: SoundSet)

    /// Puts a parameter back to the value its program gives it, or its
    /// default without a program.
    func resetToDefault(_ parameter: Parameter, in set: SoundSet)

    /// A drag on a knob begins and ends. A host records automation between
    /// the two; the app remembers the sound at the end.
    func beginEditing(_ parameter: Parameter, in set: SoundSet)
    func endEditing(_ parameter: Parameter, in set: SoundSet)

    /// The pitch of a pad, a MIDI note.
    func padNote(_ pad: Int) -> Int
    func setPadNote(_ note: Int, pad: Int)

    /// The mute group of a pad, 1...16; nil for Off.
    func padGroup(_ pad: Int) -> Int?
    func setPadGroup(_ group: Int?, pad: Int)

    /// What a pad is called: the name of the program last loaded into it.
    func padName(_ pad: Int) -> String

    /// How many times a pad has been hit; the panel flashes the pad when it changes.
    func padHits(_ pad: Int) -> Int

    /// The last note played in keyboard mode; nil if none.
    var lastNote: Int? { get }

    /// Copies the keyboard's sound and the pitch of the last note to a pad.
    func sendToPad(_ pad: Int)

    /// A hit on a pad on screen: note-on 36 + pad. Pads sound only in pad
    /// mode, where notes 36–51 are the pads.
    func hitPad(_ pad: Int, velocity: Int)

    /// The pad let go: note-off 36 + pad.
    func releasePad(_ pad: Int)

    /// A key of the on-screen keyboard pressed and let go.
    func keyDown(_ note: Int, velocity: Int)
    func keyUp(_ note: Int)

    /// Catches up with what changed elsewhere (a host's automation, MIDI, pad
    /// hits). The panel calls it every 40 ms while it is shown.
    func refresh()
}

public extension InstrumentModel {
    /// Plain (real) value of a parameter in a set.
    func value(of parameter: Parameter, in set: SoundSet) -> Float {
        parameter.plain(Float(position(of: parameter, in: set)))
    }

    /// The value as shown under a knob: "4.00 s", "800 Hz", "Alternate".
    func label(of parameter: Parameter, in set: SoundSet) -> String {
        parameter.label(value(of: parameter, in: set))
    }
}
