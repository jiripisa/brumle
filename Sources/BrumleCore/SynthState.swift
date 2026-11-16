import BrumleDSP
import Foundation

/// A set of knobs saved by name: the keyboard's or a pad's.
public struct SetState: Codable, Equatable, Sendable {
    /// The built-in program the set last loaded.
    public var program: Int
    /// Plain values by parameter identifier.
    public var values: [String: Float]

    public init(program: Int, values: [String: Float]) {
        self.program = program
        self.values = values
    }
}

/// A pad saved with its sound.
public struct PadState: Codable, Equatable, Sendable {
    public var note: Int
    /// The mute group, 1...16; nil for Off.
    public var group: Int?
    public var set: SetState

    public init(note: Int, group: Int?, set: SetState) {
        self.note = note
        self.group = group
        self.set = set
    }
}

/// Everything a host or the app saves of a Brumle: the mode, the keyboard's sound and the sixteen pads.
public struct SynthState: Codable, Equatable, Sendable {
    public var mode: PlayMode
    public var keyboard: SetState
    /// The sixteen pads, in order.
    public var pads: [PadState]

    public init(mode: PlayMode, keyboard: SetState, pads: [PadState]) {
        self.mode = mode
        self.keyboard = keyboard
        self.pads = pads
    }
}

extension Synth {

    /// The engine keeps knobs as 0...1 positions, so a plain value comes back a few ulps off what
    /// was set (429.99997 for 430). Six significant digits make the saved value stable: reading a
    /// state and writing it back reads the same state again.
    private static func stable(_ plain: Float) -> Float {
        Float(String(format: "%.6g", Double(plain))) ?? plain
    }

    private func setState(_ set: SoundSet) -> SetState {
        SetState(program: program(in: set),
                 values: Dictionary(uniqueKeysWithValues: Parameters.all.map {
                     ($0.identifier, Self.stable(value(of: $0, in: set)))
                 }))
    }

    /// Everything that is saved: read each part separately, so a state taken while audio runs may
    /// mix values from different moments.
    public var state: SynthState {
        SynthState(mode: mode,
                   keyboard: setState(.keyboard),
                   pads: (0..<Int(BRUMLE_NUM_PADS)).map { pad in
                       PadState(note: padNote(pad) ?? 0, group: padGroup(pad), set: setState(.pad(pad)))
                   })
    }

    /// Puts a saved state in. A value for a name this version does not know is ignored, a knob the
    /// state does not mention keeps its value, and fewer than sixteen pads leave the rest alone.
    public func apply(_ state: SynthState) {
        mode = state.mode
        apply(state.keyboard, to: .keyboard)
        for (pad, saved) in state.pads.prefix(Int(BRUMLE_NUM_PADS)).enumerated() {
            setPadNote(saved.note, pad: pad)
            setPadGroup(saved.group, pad: pad)
            apply(saved.set, to: .pad(pad))
        }
    }

    private func apply(_ saved: SetState, to set: SoundSet) {
        // Loading a program overwrites the whole set, so take the knobs the state does not mention
        // away first and put them back after.
        let kept = Parameters.all.filter { saved.values[$0.identifier] == nil }
            .map { ($0, normalisedValue(of: $0, in: set)) }
        if saved.program != program(in: set) { loadProgram(saved.program, into: set) }
        for (parameter, normalised) in kept { setNormalisedValue(normalised, of: parameter, in: set) }
        for (identifier, plain) in saved.values {
            if let parameter = Parameters.named(identifier) { setValue(plain, of: parameter, in: set) }
        }
    }
}
