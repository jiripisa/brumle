import BrumleDSP

/// What the keyboard plays: the keyboard's own sound at the pitch of each key, or the sixteen
/// pads, each with a sound and a pitch of its own, hit by notes 36-51.
public enum PlayMode: Int, Sendable {
    case keyboard = 0
    case pads = 1
}

/// A set of knobs: the keyboard's, or one of the sixteen pads'.
public enum SoundSet: Hashable, Sendable {
    case keyboard
    /// A pad, 0...15. A pad outside that range is no set: `Synth` ignores it.
    case pad(Int)

    /// The engine's index of the set: 0 for the keyboard, 1...16 for a pad, and -1 for a pad
    /// outside 0...15, which the engine ignores.
    var index: Int32 {
        switch self {
        case .keyboard: Int32(BRUMLE_KEYBOARD_SET)
        case .pad(let pad): Synth.padIndex(pad).map { $0 + 1 } ?? -1
        }
    }

    /// False for a pad outside 0...15.
    var exists: Bool { index >= 0 }
}

/// One Brumle: the sound engine with its parameters, pads, MIDI input and audio output.
///
/// Thread rules (the engine's own): `render` belongs to the audio thread; parameters, programs,
/// the mode, the pads and `postMIDI` may be used from any thread while audio runs. `prepare` must
/// not run while `render` does.
///
/// Pads are 0...15. A pad outside that range is ignored, as the engine ignores it: what is set
/// on it, sent to it or loaded into it goes nowhere, and reading it gives each parameter's
/// default value, program 0, and nil for its note and its group.
public final class Synth: @unchecked Sendable {

    /// The engine. Internal, so that the rest of the core can add to what a synth offers.
    let engine: OpaquePointer

    public init(sampleRate: Double = 44_100) {
        engine = brumle_create()
        brumle_prepare(engine, sampleRate)
        brumle_reset(engine)
    }

    deinit {
        brumle_destroy(engine)
    }

    /// Call before audio starts and whenever the sample rate changes. Like the engine's prepare,
    /// it also resets: every voice falls silent, the wheels go to rest and the last note is
    /// forgotten.
    public func prepare(sampleRate: Double) {
        brumle_prepare(engine, sampleRate)
    }

    /// Host frames the output lags the MIDI: the delay of the decimator below 88.2 kHz, where the
    /// voices run at twice the rate; 0 from 88.2 kHz up.
    public var latency: Int { Int(brumle_latency(engine)) }

    // MARK: Parameters

    /// Plain (real) value of a parameter in a set.
    public func value(of parameter: Parameter, in set: SoundSet = .keyboard) -> Float {
        guard set.exists else { return parameter.defaultValue }
        return brumle_get_plain(engine, set.index, Int32(parameter.index))
    }

    public func setValue(_ plain: Float, of parameter: Parameter, in set: SoundSet = .keyboard) {
        brumle_set_plain(engine, set.index, Int32(parameter.index), plain)
    }

    /// Knob position, 0...1.
    public func normalisedValue(of parameter: Parameter, in set: SoundSet = .keyboard) -> Float {
        guard set.exists else { return parameter.normalised(parameter.defaultValue) }
        return brumle_get_normalised(engine, set.index, Int32(parameter.index))
    }

    public func setNormalisedValue(_ normalised: Float, of parameter: Parameter, in set: SoundSet = .keyboard) {
        brumle_set_normalised(engine, set.index, Int32(parameter.index), normalised)
    }

    // MARK: Programs

    public func program(in set: SoundSet = .keyboard) -> Int {
        Int(brumle_get_program(engine, set.index))
    }

    /// Loads a built-in program into a set: every parameter but the octave is overwritten.
    public func loadProgram(_ index: Int, into set: SoundSet = .keyboard) {
        brumle_set_program(engine, set.index, Int32(index))
    }

    // MARK: Mode and pads

    public var mode: PlayMode {
        get { PlayMode(rawValue: Int(brumle_get_mode(engine))) ?? .keyboard }
        set { brumle_set_mode(engine, Int32(newValue.rawValue)) }
    }

    /// The pitch of a pad, a MIDI note; nil for a pad outside 0...15.
    public func padNote(_ pad: Int) -> Int? {
        guard let index = Self.padIndex(pad) else { return nil }
        return Int(brumle_pad_note(engine, index))
    }

    public func setPadNote(_ note: Int, pad: Int) {
        guard let index = Self.padIndex(pad) else { return }
        brumle_set_pad_note(engine, index, Int32(Self.dataByte(note)))
    }

    /// The mute group of a pad, 1...16; nil for Off, and for a pad outside 0...15.
    public func padGroup(_ pad: Int) -> Int? {
        guard let index = Self.padIndex(pad) else { return nil }
        let group = Int(brumle_pad_group(engine, index))
        return group > 0 ? group : nil
    }

    public func setPadGroup(_ group: Int?, pad: Int) {
        guard let index = Self.padIndex(pad) else { return }
        brumle_set_pad_group(engine, index, Int32(group ?? 0))
    }

    /// The last note played in keyboard mode since the last reset; nil if none.
    public var lastNote: Int? {
        let note = Int(brumle_last_note(engine))
        return note >= 0 ? note : nil
    }

    /// Copies the keyboard's sound (and its program) and the pitch of the last note (36 if none)
    /// to a pad; the pad keeps its group. The copy goes value by value, not as a whole: a pad hit
    /// landing mid-copy freezes a mix of old and new values for that one hit.
    public func sendToPad(_ pad: Int) {
        guard let index = Self.padIndex(pad) else { return }
        brumle_send_to_pad(engine, index)
    }

    /// Puts the built-in kit into every pad (sound, pitch and group). Copies value by value like
    /// `sendToPad`: a pad hit landing mid-load freezes a mix of old and new values for that hit.
    public func loadDefaultKit() {
        brumle_load_default_kit(engine)
    }

    /// Voices playing and not being choked (at most 16).
    public var soundingVoices: Int { Int(brumle_sounding_voices(engine)) }

    /// The engine's index of a pad; nil outside 0...15.
    fileprivate static func padIndex(_ pad: Int) -> Int32? {
        pad >= 0 && pad < Int(BRUMLE_NUM_PADS) ? Int32(pad) : nil
    }

    // MARK: MIDI

    /// A MIDI channel-voice message from any thread; it plays at the start of the next rendered
    /// block.
    public func postMIDI(status: UInt8, data1: UInt8, data2: UInt8) {
        brumle_post_midi(engine, Int32(status), Int32(data1), Int32(data2), 0)
    }

    /// Notes and velocities outside 0...127 count as the nearest valid one; the softest hit is
    /// velocity 1, because 0 means note-off in MIDI.
    public func noteOn(_ note: Int, velocity: Int = 100) {
        postMIDI(status: 0x90, data1: Self.dataByte(note), data2: max(1, Self.dataByte(velocity)))
    }

    public func noteOff(_ note: Int) {
        postMIDI(status: 0x80, data1: Self.dataByte(note), data2: 0)
    }

    /// A MIDI data byte: 0...127.
    private static func dataByte(_ value: Int) -> UInt8 {
        UInt8(min(max(value, 0), 127))
    }

    public func allNotesOff() {
        postMIDI(status: 0xB0, data1: 123, data2: 0)
    }

    /// Lets go of everything a MIDI source may have left behind when it went away: every note,
    /// pitch bend, the mod wheel and aftertouch.
    public func releaseAll() {
        allNotesOff()
        postMIDI(status: 0xE0, data1: 0, data2: 0x40)       // pitch bend centred
        postMIDI(status: 0xB0, data1: 1, data2: 0)          // mod wheel down
        postMIDI(status: 0xD0, data1: 0, data2: 0)          // no aftertouch
    }

    // MARK: Audio

    /// Renders `frames` samples in stereo: Pan places each voice between the two buffers.
    /// `right` may be nil: `left` then gets the left channel. Audio thread only.
    public func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?, frames: Int) {
        brumle_process(engine, left, right, Int32(frames))
    }
}
