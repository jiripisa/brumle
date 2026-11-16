import AudioToolbox
import BrumleCore
import BrumleUI
import Observation

/// The panel's model in a host, over the Audio Unit and its engine.
///
/// - The keyboard's set is the unit's parameters (their values are the engine's plain values, a
///   parameter's ID is its index). Knobs set them with `AUParameterSet` and gesture events, so
///   that a host records automation; its programs are the unit's factory presets.
/// - Everything else is no parameter: the pads' sets, notes and groups, the mode, and the keys
///   and pads played on screen go straight to the unit's engine (`kBrumleProperty_Engine`). After
///   such an edit the unit is told (`kBrumleProperty_StateChanged`) and the host marks the
///   project edited.
///
/// A host changes parameters and restores projects without telling a view, so the panel asks for
/// the present state every 40 ms: see `refresh`.
///
/// The engine is borrowed from the unit. Before each use the model asks the unit for it again;
/// once the unit no longer gives the same engine (the host disposed of it while the window was
/// still shown), the model is detached: it never touches the unit or the engine again.
@MainActor
@Observable
public final class AudioUnitModel: InstrumentModel {

    @ObservationIgnored private let unit: AudioUnit
    /// The unit's engine, borrowed: the unit owns it. Used only while `isAttached`.
    @ObservationIgnored private let engine: OpaquePointer
    @ObservationIgnored private let synth: Synth
    /// True once the unit was found gone: nothing is asked of it or its engine any more.
    @ObservationIgnored private(set) var isDetached = false
    /// When the host is to hear that the pads or the mode changed: half a second after the last
    /// such edit, so that a drag, which edits many times a second, is told once.
    @ObservationIgnored private var hostNotice = SaveDebounce()
    /// The keys and pads the mouse holds, let go of when the window closes.
    @ObservationIgnored private var held = HeldNotes()

    /// Every set, as the panel names them: the keyboard's, then the pads'.
    private static let sets = [SoundSet.keyboard] + (0..<PadGrid.count).map(SoundSet.pad)

    // What the panel shows, mirrored from the unit and the engine: the panel sees only what
    // changes here.

    /// Knob positions (0...1) by parameter index, for every set.
    private var positions: [SoundSet: [Float]]
    /// The program each set last loaded.
    private var programs: [SoundSet: Int]
    private var padNotes: [Int]
    private var padGroups: [Int?]
    /// The pads' hit counters as of the last `refresh`.
    private var hits: [Int]
    public private(set) var lastNote: Int?
    private var playMode: PlayMode

    public var mode: PlayMode {
        get { playMode }
        set {
            guard newValue != playMode, isAttached else { return }
            synth.mode = newValue
            playMode = synth.mode
            edited()
        }
    }

    /// The pad the knobs edit in pad mode. The window's own: a new window begins on pad 01.
    public var selectedPad = 0 {
        didSet { if selectedPad != oldValue, isAttached { mirror(.pad(selectedPad)) } }
    }

    public var shownSet: SoundSet { playMode == .keyboard ? .keyboard : .pad(selectedPad) }

    /// The model of a unit's window; nil for a unit that does not hand out its engine (not Brumle's).
    public init?(unit: AudioUnit) {
        guard let engine = Self.engine(of: unit) else { return nil }
        self.unit = unit
        self.engine = engine
        let synth = Synth(borrowing: engine)
        self.synth = synth
        positions = Dictionary(uniqueKeysWithValues: Self.sets.map { set in
            (set, set == .keyboard ? Self.keyboardPositions(of: unit) : Self.positions(in: set, of: synth))
        })
        programs = Self.programs(of: synth)
        padNotes = Self.padNotes(of: synth)
        padGroups = (0..<PadGrid.count).map(synth.padGroup)
        hits = (0..<PadGrid.count).map(synth.padHits)
        lastNote = synth.lastNote
        playMode = synth.mode
    }

    /// Takes over what changed elsewhere since the last look: the host's automation, presets and
    /// restored projects, and on the audio thread the pads hit (also from MIDI) and the last note.
    /// Tells the host of the window's pad edits once they have rested.
    public func refresh() {
        guard isAttached else { return }
        let keyboard = Self.keyboardPositions(of: unit)
        if keyboard != positions[.keyboard] { positions[.keyboard] = keyboard }
        if case .pad = shownSet { mirror(shownSet) }          // a restored project changes the pads too
        let programs = Self.programs(of: synth)
        if programs != self.programs { self.programs = programs }
        let notes = Self.padNotes(of: synth)
        if notes != padNotes { padNotes = notes }
        let groups = (0..<PadGrid.count).map(synth.padGroup)
        if groups != padGroups { padGroups = groups }
        let hits = (0..<PadGrid.count).map(synth.padHits)
        if hits != self.hits { self.hits = hits }
        let note = synth.lastNote
        if note != lastNote { lastNote = note }
        let mode = synth.mode
        if mode != playMode { playMode = mode }
        if hostNotice.isDue(at: .now) { tellHost() }
    }

    // MARK: Knobs and programs

    public func program(in set: SoundSet) -> Int {
        programs[set] ?? 0          // a pad outside 0...15, as `Synth` reads it
    }

    /// Into the keyboard as the unit's factory preset, so that the host shows it; into a pad
    /// through the engine.
    public func loadProgram(_ index: Int, into set: SoundSet) {
        guard Programs.names.indices.contains(index), positions[set] != nil, isAttached else { return }
        if set == .keyboard {
            guard setPresentPreset(number: index, name: Programs.names[index]) else { return }
            everyParameterMoved()
        } else {
            synth.loadProgram(index, into: set)
            mirror(set)
            edited()
        }
    }

    public func position(of parameter: Parameter, in set: SoundSet) -> Double {
        Double(positions[set]?[parameter.index] ?? parameter.normalised(parameter.defaultValue))
    }

    public func setPosition(_ position: Double, of parameter: Parameter, in set: SoundSet) {
        guard positions[set] != nil, isAttached else { return }
        let plain = parameter.plain(Float(min(max(position, 0), 1)))      // integers and choices on their step
        if set == .keyboard {
            var address = address(of: parameter)
            AUParameterSet(nil, nil, &address, plain, 0)      // sets the value and tells the host's listeners
            positions[set]?[parameter.index] = parameter.normalised(plain)
        } else {
            synth.setValue(plain, of: parameter, in: set)
            positions[set]?[parameter.index] = synth.normalisedValue(of: parameter, in: set)
            edited()
        }
    }

    public func resetToDefault(_ parameter: Parameter, in set: SoundSet) {
        let program = program(in: set)
        let plain = Programs.names.indices.contains(program)
            ? Programs.value(program: program, parameter: parameter)
            : parameter.defaultValue
        setPosition(Double(parameter.normalised(plain)), of: parameter, in: set)
    }

    /// A host records automation between the two. The pads' knobs are no parameters of the unit:
    /// there is nothing to record.
    public func beginEditing(_ parameter: Parameter, in set: SoundSet) {
        if set == .keyboard, isAttached { notify(.beginParameterChangeGesture, parameter) }
    }

    public func endEditing(_ parameter: Parameter, in set: SoundSet) {
        if set == .keyboard, isAttached { notify(.endParameterChangeGesture, parameter) }
    }

    // MARK: Pads

    public func padNote(_ pad: Int) -> Int {
        padNotes.indices.contains(pad) ? padNotes[pad] : PadGrid.note(ofPad: pad)
    }

    public func setPadNote(_ note: Int, pad: Int) {
        guard padNotes.indices.contains(pad), isAttached else { return }
        synth.setPadNote(note, pad: pad)
        padNotes[pad] = synth.padNote(pad) ?? note
        edited()
    }

    public func padGroup(_ pad: Int) -> Int? {
        padGroups.indices.contains(pad) ? padGroups[pad] : nil
    }

    public func setPadGroup(_ group: Int?, pad: Int) {
        guard padGroups.indices.contains(pad), isAttached else { return }
        synth.setPadGroup(group, pad: pad)
        padGroups[pad] = synth.padGroup(pad)
        edited()
    }

    public func padName(_ pad: Int) -> String {
        PadLabel.name(program: program(in: .pad(pad)))
    }

    public func padHits(_ pad: Int) -> Int {
        hits.indices.contains(pad) ? hits[pad] : 0
    }

    /// The engine copies its keyboard set, which takes the unit's parameters at the next render:
    /// they go to the engine first, so that a knob just turned or a program just chosen is sent
    /// too, whether the host renders or not.
    public func sendToPad(_ pad: Int) {
        guard padNotes.indices.contains(pad), isAttached else { return }
        for parameter in Parameters.all {
            synth.setValue(Self.value(of: parameter, in: unit), of: parameter, in: .keyboard)
        }
        synth.sendToPad(pad)
        mirror(.pad(pad))
        padNotes[pad] = synth.padNote(pad) ?? padNotes[pad]
        edited()
    }

    // MARK: Playing on screen

    /// Selects the pad too, so that the knobs show what was just heard.
    public func hitPad(_ pad: Int, velocity: Int) {
        guard padNotes.indices.contains(pad), isAttached else { return }
        selectedPad = pad
        held.padDown(pad)
        synth.noteOn(PadGrid.note(ofPad: pad), velocity: velocity)
    }

    public func releasePad(_ pad: Int) {
        guard padNotes.indices.contains(pad), isAttached else { return }
        held.padUp(pad)
        synth.noteOff(PadGrid.note(ofPad: pad))
    }

    public func keyDown(_ note: Int, velocity: Int) {
        guard isAttached else { return }
        held.keyDown(note)
        synth.noteOn(note, velocity: velocity)
    }

    public func keyUp(_ note: Int) {
        guard isAttached else { return }
        held.keyUp(note)
        synth.noteOff(note)
    }

    /// Lets go of every key and pad the mouse holds: when the window closes, the mouse-up may
    /// never arrive.
    public func releaseHeld() {
        let notes = held.releaseAll()
        guard isAttached else { return }
        for note in notes { synth.noteOff(note) }
    }

    // MARK: Telling the host

    /// The pads or the mode changed: tell the host once the edits have rested.
    private func edited() {
        hostNotice.edited(at: .now)
    }

    /// Tells the host now if an edit is waiting: when the window closes.
    public func tellHostIfEdited() {
        if hostNotice.isPending, isAttached { tellHost() }
    }

    /// The unit tells the host its saved state changed, and the host marks the project edited.
    private func tellHost() {
        hostNotice.saved()
        var any: UInt32 = 1
        AudioUnitSetProperty(unit, Self.stateChangedProperty, kAudioUnitScope_Global, 0, &any, UInt32(MemoryLayout<UInt32>.size))
    }

    // MARK: Mirroring

    /// Takes over what the engine now holds for a pad's set.
    private func mirror(_ set: SoundSet) {
        guard set != .keyboard, positions[set] != nil else { return }
        let values = Self.positions(in: set, of: synth)
        if values != positions[set] { positions[set] = values }
        let program = synth.program(in: set)
        if program != programs[set] { programs[set] = program }
    }

    /// Every parameter may have moved (a preset): tell the host's listeners, then read them back.
    private func everyParameterMoved() {
        var all = AudioUnitParameter(mAudioUnit: unit, mParameterID: kAUParameterListener_AnyParameter,
                                     mScope: kAudioUnitScope_Global, mElement: 0)
        AUParameterListenerNotify(nil, nil, &all)
        refresh()
    }

    private static func positions(in set: SoundSet, of synth: Synth) -> [Float] {
        Parameters.all.map { synth.normalisedValue(of: $0, in: set) }
    }

    /// The program of every set. The keyboard's comes from the engine too: after a project is
    /// reopened the unit's present preset has no number, but the engine knows it.
    private static func programs(of synth: Synth) -> [SoundSet: Int] {
        Dictionary(uniqueKeysWithValues: sets.map { ($0, synth.program(in: $0)) })
    }

    private static func padNotes(of synth: Synth) -> [Int] {
        (0..<PadGrid.count).map { synth.padNote($0) ?? PadGrid.note(ofPad: $0) }
    }

    // MARK: The Audio Unit

    /// The unit's own properties for its window. The numbers are those of
    /// `kBrumleProperty_Engine` and `kBrumleProperty_StateChanged` in BrumleAU.h and must stay in
    /// step with them.
    static let engineProperty: AudioUnitPropertyID = 64001
    static let stateChangedProperty: AudioUnitPropertyID = 64002

    /// Whether the unit is still there with the engine the model borrowed. Asking a disposed unit
    /// is safe: the Audio Unit API checks the instance and returns an error.
    private var isAttached: Bool {
        if !isDetached, Self.engine(of: unit) != engine { isDetached = true }
        return !isDetached
    }

    private static func engine(of unit: AudioUnit) -> OpaquePointer? {
        var engine: UnsafeMutableRawPointer?
        var size = UInt32(MemoryLayout<UnsafeMutableRawPointer?>.size)
        guard AudioUnitGetProperty(unit, engineProperty, kAudioUnitScope_Global, 0, &engine, &size) == noErr,
              let engine else { return nil }
        return OpaquePointer(engine)
    }

    private func address(of parameter: Parameter) -> AudioUnitParameter {
        AudioUnitParameter(mAudioUnit: unit, mParameterID: AudioUnitParameterID(parameter.index),
                           mScope: kAudioUnitScope_Global, mElement: 0)
    }

    private func notify(_ type: AudioUnitEventType, _ parameter: Parameter) {
        var event = AudioUnitEvent(mEventType: type, mArgument: .init(mParameter: address(of: parameter)))
        AUEventListenerNotify(nil, nil, &event)
    }

    private static func keyboardPositions(of unit: AudioUnit) -> [Float] {
        Parameters.all.map { $0.normalised(value(of: $0, in: unit)) }
    }

    /// A parameter's plain value in the unit.
    private static func value(of parameter: Parameter, in unit: AudioUnit) -> Float {
        var plain: AudioUnitParameterValue = 0
        guard AudioUnitGetParameter(unit, AudioUnitParameterID(parameter.index), kAudioUnitScope_Global, 0, &plain) == noErr else {
            return parameter.defaultValue
        }
        return plain
    }

    /// Chooses a factory preset by its number. The unit keeps the name, so it has to live
    /// through the call.
    private func setPresentPreset(number: Int, name: String) -> Bool {
        let held = name as CFString
        return withExtendedLifetime(held) {
            var preset = AUPreset(presetNumber: Int32(number), presetName: Unmanaged.passUnretained(held))
            return AudioUnitSetProperty(unit, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0,
                                        &preset, UInt32(MemoryLayout<AUPreset>.size)) == noErr
        }
    }
}
