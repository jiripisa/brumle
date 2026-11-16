import AudioToolbox
import Foundation
import Testing
import BrumleAU
import BrumleDSP
@testable import BrumleCore

/// The Audio Unit, registered with this process only (no component bundle) under a subtype of
/// its own, so that an installed copy stays out of it. The plug-in window's tests use it too.
@MainActor
enum PlugIn {

    static let component: AudioComponent = {
        var description = AudioComponentDescription(componentType: kAudioUnitType_MusicDevice,
                                                    componentSubType: 0x4272_6D74,          // 'Brmt'
                                                    componentManufacturer: 0x4A50_6973,     // 'JPis'
                                                    componentFlags: 0, componentFlagsMask: 0)
        let factory = unsafeBitCast(BrumleAUFactory as @convention(c) (UnsafePointer<AudioComponentDescription>?) -> UnsafeMutableRawPointer?,
                                    to: AudioComponentFactoryFunction.self)
        return AudioComponentRegister(&description, "Brumle under test" as CFString, 0, factory)
    }()
}

/// One instance of the unit, played the way a host plays it: initialised at a sample rate with
/// a number of output channels, rendered block after block. The plug-in window's tests use it too.
@MainActor
final class Instrument {

    let unit: AudioUnit
    let rate: Double
    let channels: Int
    /// Rendered blocks so far: a unit renders a point in time only once, so every block has a
    /// time of its own.
    private var blocks = 0
    static let frames = 256

    init(rate: Double = 48_000, channels: Int = 2) throws {
        var made: AudioUnit?
        try #require(AudioComponentInstanceNew(PlugIn.component, &made) == noErr)
        unit = try #require(made)
        self.rate = rate
        self.channels = channels
        try initialise(rate: rate, channels: channels)
    }

    isolated deinit {
        AudioComponentInstanceDispose(unit)
    }

    /// Sets the output format and initialises, as a host does before it plays.
    func initialise(rate: Double, channels: Int) throws {
        var format = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
                                                 mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
                                                 mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                                                 mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
        try #require(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &format,
                                          UInt32(MemoryLayout<AudioStreamBasicDescription>.size)) == noErr)
        try #require(AudioUnitInitialize(unit) == noErr)
    }

    /// One block of every output channel. MIDI sent before it is played in it.
    func render() throws -> [[Float]] {
        let frames = UInt32(Self.frames)
        var flags = AudioUnitRenderActionFlags()
        var time = AudioTimeStamp()
        time.mFlags = .sampleTimeValid
        time.mSampleTime = Float64(blocks * Self.frames)
        blocks += 1
        let buffers = AudioBufferList.allocate(maximumBuffers: channels)     // the unit fills buffers of its own
        defer { free(buffers.unsafeMutablePointer) }
        for index in 0..<channels { buffers[index] = AudioBuffer(mNumberChannels: 1, mDataByteSize: frames * 4, mData: nil) }
        try #require(AudioUnitRender(unit, &flags, &time, 0, frames, buffers.unsafeMutablePointer) == noErr)
        return (0..<channels).map { index in
            let data = buffers[index].mData!.assumingMemoryBound(to: Float.self)
            return Array(UnsafeBufferPointer(start: data, count: Self.frames))
        }
    }

    /// Every channel of `seconds` of output, block after block.
    func render(seconds: Double) throws -> [[Float]] {
        var out = [[Float]](repeating: [], count: channels)
        for _ in 0..<Int((seconds * rate / Double(Self.frames)).rounded(.up)) {
            for (index, channel) in try render().enumerated() { out[index] += channel }
        }
        return out
    }

    func midi(_ status: UInt32, _ data1: UInt32, _ data2: UInt32) throws {
        try #require(MusicDeviceMIDIEvent(unit, status, data1, data2, 0) == noErr)
    }

    func setParameter(_ identifier: String, to value: Float) throws {
        let parameter = try #require(Parameters.named(identifier))
        try #require(AudioUnitSetParameter(unit, AudioUnitParameterID(parameter.index), kAudioUnitScope_Global, 0, value, 0) == noErr)
    }

    /// The unit's own value of a parameter, as a host reads it.
    func parameter(_ index: Int) throws -> Float {
        var value: AudioUnitParameterValue = 0
        try #require(AudioUnitGetParameter(unit, AudioUnitParameterID(index), kAudioUnitScope_Global, 0, &value) == noErr)
        return value
    }

    /// The engine behind the unit, as the plug-in's window gets it.
    func engine() throws -> OpaquePointer {
        var pointer: UnsafeMutableRawPointer?
        var size = UInt32(MemoryLayout<UnsafeMutableRawPointer?>.size)
        try #require(AudioUnitGetProperty(unit, AudioUnitPropertyID(kBrumleProperty_Engine), kAudioUnitScope_Global, 0, &pointer, &size) == noErr)
        return OpaquePointer(try #require(pointer))
    }

    /// The unit's saved state, as a host saves it with a project.
    func classInfo() throws -> CFPropertyList {
        var state: Unmanaged<CFPropertyList>?
        var size = UInt32(MemoryLayout<Unmanaged<CFPropertyList>?>.size)
        try #require(AudioUnitGetProperty(unit, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, 0, &state, &size) == noErr)
        return try #require(state).takeRetainedValue()        // the unit hands its state over retained
    }

    func restore(_ state: CFPropertyList) throws {
        var saved = Unmanaged.passUnretained(state)
        try withExtendedLifetime(state) {
            try #require(AudioUnitSetProperty(unit, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, 0, &saved,
                                              UInt32(MemoryLayout<Unmanaged<CFPropertyList>>.size)) == noErr)
        }
    }

    /// Chooses a factory preset (a program), as a host's preset menu does.
    func loadPreset(_ number: Int) throws {
        let name = Programs.names[number] as CFString
        var preset = AUPreset(presetNumber: Int32(number), presetName: Unmanaged.passUnretained(name))
        try withExtendedLifetime(name) {
            try #require(AudioUnitSetProperty(unit, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0,
                                              &preset, UInt32(MemoryLayout<AUPreset>.size)) == noErr)
        }
    }

    func float64Property(_ id: AudioUnitPropertyID) throws -> Float64 {
        var value: Float64 = -1
        var size = UInt32(MemoryLayout<Float64>.size)
        try #require(AudioUnitGetProperty(unit, id, kAudioUnitScope_Global, 0, &value, &size) == noErr)
        return value
    }
}

private func peak(_ samples: [Float]) -> Float {
    samples.reduce(0) { max($0, abs($1)) }
}

/// How many times a host's property listener was called. The unit calls it synchronously.
final class Calls {
    var count = 0
}

@Suite("The Audio Unit")
@MainActor
struct AudioUnitTests {

    // MARK: Parameters and programs

    @Test("The parameters are the keyboard set, grouped as the engine's sections")
    func parametersAreTheKeyboardSet() throws {
        let instrument = try Instrument()
        let unit = instrument.unit

        var size: UInt32 = 0
        try #require(AudioUnitGetPropertyInfo(unit, kAudioUnitProperty_ParameterList, kAudioUnitScope_Global, 0, &size, nil) == noErr)
        var ids = [AudioUnitParameterID](repeating: 0, count: Int(size) / MemoryLayout<AudioUnitParameterID>.size)
        try #require(AudioUnitGetProperty(unit, kAudioUnitProperty_ParameterList, kAudioUnitScope_Global, 0, &ids, &size) == noErr)
        #expect(Parameters.all.count == 81)
        #expect(ids == (0..<81).map { AudioUnitParameterID($0) })

        var sectionOf: [Int: Int] = [:]
        for (section, group) in ParameterSection.all.enumerated() {
            for parameter in group.parameters { sectionOf[parameter.index] = section }
        }
        for parameter in Parameters.all {
            var info = AudioUnitParameterInfo()
            var infoSize = UInt32(MemoryLayout<AudioUnitParameterInfo>.size)
            try #require(AudioUnitGetProperty(unit, kAudioUnitProperty_ParameterInfo, kAudioUnitScope_Global,
                                              AudioUnitElement(parameter.index), &info, &infoSize) == noErr)
            let name = info.flags.contains(.flag_CFNameRelease) ? info.cfNameString?.takeRetainedValue() : info.cfNameString?.takeUnretainedValue()
            #expect(name as String? == parameter.name)
            #expect(info.minValue == parameter.range.lowerBound && info.maxValue == parameter.range.upperBound, "\(parameter.identifier)")
            #expect(info.defaultValue == parameter.defaultValue, "\(parameter.identifier)")
            #expect(info.flags.contains(.flag_IsReadable) && info.flags.contains(.flag_IsWritable))
            if let section = sectionOf[parameter.index] {
                #expect(info.flags.contains(.flag_HasClump) && info.clumpID == UInt32(section + 1), "\(parameter.identifier)")
            } else {
                #expect(!info.flags.contains(.flag_HasClump), "\(parameter.identifier) is in no section")
            }
            if case .choice(let choices) = parameter.kind {
                #expect(info.unit == .indexed)
                var strings: Unmanaged<CFArray>?
                var stringsSize = UInt32(MemoryLayout<Unmanaged<CFArray>?>.size)
                try #require(AudioUnitGetProperty(unit, kAudioUnitProperty_ParameterValueStrings, kAudioUnitScope_Global,
                                                  AudioUnitElement(parameter.index), &strings, &stringsSize) == noErr)
                #expect(try #require(strings).takeRetainedValue() as? [String] == choices)
            }
        }
        #expect(sectionOf.count == 34)

        for (section, group) in ParameterSection.all.enumerated() {
            var clump = AudioUnitParameterNameInfo(inID: AudioUnitParameterID(section + 1), inDesiredLength: Int32(kAudioUnitParameterName_Full), outName: nil)
            var clumpSize = UInt32(MemoryLayout<AudioUnitParameterNameInfo>.size)
            try #require(AudioUnitGetProperty(unit, kAudioUnitProperty_ParameterClumpName, kAudioUnitScope_Global, 0, &clump, &clumpSize) == noErr)
            #expect(try #require(clump.outName).takeRetainedValue() as String == group.title)
        }
    }

    @Test("A note sent by the host sounds in both channels within 100 ms at 48 kHz")
    func noteRenders() throws {
        let instrument = try Instrument(rate: 48_000)
        try instrument.midi(0x90, 60, 100)
        let out = try instrument.render(seconds: 0.1)
        #expect(out.count == 2)
        #expect(peak(out[0]) > 0.01 && peak(out[1]) > 0.01)
    }

    @Test("A parameter the host sets reaches the engine's keyboard set by the next render")
    func hostParameterReachesEngine() throws {
        let instrument = try Instrument()
        let engine = try instrument.engine()
        let ring = try #require(Parameters.named("ring"))
        try instrument.setParameter("ring", to: 9)
        _ = try instrument.render()
        #expect(abs(brumle_get_plain(engine, Int32(BRUMLE_KEYBOARD_SET), Int32(ring.index)) - 9) < 0.001)
        #expect(brumle_get_plain(engine, 1, Int32(ring.index)) != 9)        // a pad's set is not the unit's
    }

    @Test("A factory preset loads its program into the keyboard set and leaves the octave alone")
    func factoryPresetLoadsProgram() throws {
        let instrument = try Instrument()
        let engine = try instrument.engine()
        let octave = try #require(Parameters.named("octave"))
        try instrument.setParameter("octave", to: 1)
        _ = try instrument.render()

        try instrument.loadPreset(2)
        _ = try instrument.render()

        var present = AUPreset()
        var size = UInt32(MemoryLayout<AUPreset>.size)
        try #require(AudioUnitGetProperty(instrument.unit, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0, &present, &size) == noErr)
        present.presetName?.release()
        #expect(present.presetNumber == 2)
        #expect(brumle_get_program(engine, Int32(BRUMLE_KEYBOARD_SET)) == 2)
        for parameter in Parameters.all where parameter != octave {
            let value = Programs.value(program: 2, parameter: parameter)
            #expect(try instrument.parameter(parameter.index) == value, "\(parameter.identifier)")
            #expect(abs(brumle_get_plain(engine, Int32(BRUMLE_KEYBOARD_SET), Int32(parameter.index)) - value) <= 0.001 * max(1, abs(value)),
                    "\(parameter.identifier)")
        }
        #expect(try instrument.parameter(octave.index) == 1)
        #expect(brumle_get_plain(engine, Int32(BRUMLE_KEYBOARD_SET), Int32(octave.index)) == 1)
    }

    // MARK: Saved state

    @Test("The saved state brings back the keyboard set, the pads and the mode")
    func stateRoundTrip() throws {
        let saved = try Instrument()
        let synth = Synth(borrowing: try saved.engine())
        let vowel = try #require(Parameters.named("vowel")), buzz = try #require(Parameters.named("buzz"))
        synth.loadProgram(4, into: .pad(3))
        synth.setValue(1500, of: vowel, in: .pad(3))
        synth.setPadNote(60, pad: 3)
        synth.setPadGroup(7, pad: 3)
        synth.setPadGroup(nil, pad: 0)
        synth.mode = .pads
        try saved.setParameter("buzz", to: 55)
        _ = try saved.render()
        let state = try saved.classInfo()

        let restored = try Instrument()
        let other = Synth(borrowing: try restored.engine())
        #expect(other.state != synth.state)
        try restored.restore(state)
        _ = try restored.render()

        #expect(try restored.parameter(buzz.index) == 55)
        #expect(other.state == synth.state)
        #expect(other.mode == .pads && other.padNote(3) == 60 && other.padGroup(3) == 7 && other.padGroup(0) == nil)
        #expect(other.program(in: .pad(3)) == 4 && abs(other.value(of: vowel, in: .pad(3)) - 1500) < 0.5)
    }

    @Test("A pad's shorter list of values covers the first parameters; the later ones stay at their defaults")
    func stateShorterValues() throws {
        let saved = try Instrument()
        let synth = Synth(borrowing: try saved.engine())
        let amount = try #require(Parameters.named("lfo1vowel"))
        #expect(amount.index >= 34)
        synth.setValue(1500, of: try #require(Parameters.named("vowel")), in: .pad(3))
        synth.setValue(50, of: amount, in: .pad(3))
        let state = try #require(try saved.classInfo() as? [String: Any])

        // The state as a version with only the first 34 parameters saved it.
        var pads = try #require(state["brumle-pads"] as? [String: Any])
        var list = try #require(pads["pads"] as? [[String: Any]])
        #expect(list.count == 16)
        let values = try #require(list[3]["values"] as? Data)
        #expect(values.count == 81 * MemoryLayout<Float32>.size)
        list[3]["values"] = values.prefix(34 * MemoryLayout<Float32>.size)
        pads["pads"] = list
        var older = state
        older["brumle-pads"] = pads

        let restored = try Instrument()
        try restored.restore(older as CFDictionary)
        let other = Synth(borrowing: try restored.engine())
        // The engine keeps knobs as 0...1 positions: a plain value comes back a few ulps off.
        for parameter in Parameters.all {
            if parameter.index < 34 {
                let value = synth.value(of: parameter, in: .pad(3))
                #expect(abs(other.value(of: parameter, in: .pad(3)) - value) <= 1e-5 * max(1, abs(value)), "\(parameter.identifier)")
            } else {
                #expect(other.value(of: parameter, in: .pad(3)) == parameter.defaultValue, "\(parameter.identifier)")
            }
        }
    }

    @Test("A reopened project keeps the keyboard's program, so a reset goes to that program's value")
    func stateKeepsTheKeyboardProgram() throws {
        let saved = try Instrument()
        try saved.loadPreset(3)                                 // Morsing: Ring 1 s
        try saved.setParameter("buzz", to: 55)
        _ = try saved.render()
        let state = try saved.classInfo()

        let restored = try Instrument()
        let other = Synth(borrowing: try restored.engine())
        try restored.restore(state)
        _ = try restored.render()
        let ring = try #require(Parameters.named("ring")), buzz = try #require(Parameters.named("buzz"))
        #expect(other.program(in: .keyboard) == 3)
        #expect(try restored.parameter(buzz.index) == 55)       // the values are the project's, not the program's
        #expect(abs(other.value(of: buzz, in: .keyboard) - 55) < 0.001)
        #expect(Programs.value(program: other.program(in: .keyboard), parameter: ring) == 1)

        // A state without the key leaves the index alone.
        var older = try #require(state as? [String: Any])
        var pads = try #require(older["brumle-pads"] as? [String: Any])
        #expect(pads["keyboardProgram"] as? Int == 3)
        pads["keyboardProgram"] = nil
        older["brumle-pads"] = pads
        let another = try Instrument()
        try another.loadPreset(5)
        try another.restore(older as CFDictionary)
        #expect(brumle_get_program(try another.engine(), Int32(BRUMLE_KEYBOARD_SET)) == 5)
    }

    @Test("Saved state of the wrong shape is ignored, part by part")
    func stateOfTheWrongShape() throws {
        let saved = try Instrument()
        let state = try #require(try saved.classInfo() as? [String: Any])
        let restored = try Instrument()
        let synth = Synth(borrowing: try restored.engine())
        let before = synth.state

        var pads = try #require(state["brumle-pads"] as? [String: Any])
        var list = try #require(pads["pads"] as? [Any])
        list[0] = 42                                                        // not a pad
        list[1] = ["note": "C3", "group": 2.5, "program": [1], "values": "loud"] as [String: Any]
        list[2] = ["values": Data([0x01, 0x02, 0x03])] as [String: Any]     // shorter than one value
        list.append(["note": 70] as [String: Any])                          // a 17th pad
        pads["pads"] = list
        pads["mode"] = "pads"
        pads["keyboardProgram"] = Data([3])
        var wrong = state
        wrong["brumle-pads"] = pads
        try restored.restore(wrong as CFDictionary)
        #expect(synth.state == before)

        for shape: Any in [7, "pads", [1, 2]] {
            wrong["brumle-pads"] = shape
            try restored.restore(wrong as CFDictionary)
        }
        pads["pads"] = ["pad": 1]
        wrong["brumle-pads"] = pads
        try restored.restore(wrong as CFDictionary)
        #expect(synth.state == before)
    }

    @Test("Telling the unit its pads changed tells the host its saved state changed")
    func stateChangedTellsTheHost() throws {
        let instrument = try Instrument()
        let calls = Calls()
        let listener: AudioUnitPropertyListenerProc = { refCon, _, id, scope, _ in
            guard id == kAudioUnitProperty_ClassInfo, scope == kAudioUnitScope_Global else { return }
            Unmanaged<Calls>.fromOpaque(refCon).takeUnretainedValue().count += 1
        }
        let refCon = Unmanaged.passUnretained(calls).toOpaque()
        try #require(AudioUnitAddPropertyListener(instrument.unit, kAudioUnitProperty_ClassInfo, listener, refCon) == noErr)
        defer { AudioUnitRemovePropertyListenerWithUserData(instrument.unit, kAudioUnitProperty_ClassInfo, listener, refCon) }

        var any: UInt32 = 1
        try #require(AudioUnitSetProperty(instrument.unit, AudioUnitPropertyID(kBrumleProperty_StateChanged), kAudioUnitScope_Global, 0,
                                          &any, UInt32(MemoryLayout<UInt32>.size)) == noErr)
        #expect(calls.count == 1)
    }

    // MARK: Latency, tail and output

    @Test("The latency follows the sample rate: 29 frames below 88.2 kHz, none above")
    func latencyFollowsRate() throws {
        let instrument = try Instrument(rate: 44_100)
        #expect(abs(try instrument.float64Property(kAudioUnitProperty_Latency) - 29.0 / 44_100) < 1e-12)
        for (rate, latency) in [(48_000.0, 29.0 / 48_000), (96_000, 0), (44_100, 29.0 / 44_100)] {
            try #require(AudioUnitUninitialize(instrument.unit) == noErr)
            try instrument.initialise(rate: rate, channels: 2)
            #expect(abs(try instrument.float64Property(kAudioUnitProperty_Latency) - latency) < 1e-12, "\(rate) Hz")
        }
    }

    @Test("The tail is as long as the longest Ring")
    func tailIsTheLongestRing() throws {
        let instrument = try Instrument()
        let ring = try #require(Parameters.named("ring"))
        #expect(try instrument.float64Property(kAudioUnitProperty_TailTime) == Float64(ring.range.upperBound))
    }

    @Test("A mono output gets both sides mixed: (L+R)/2, so a pad panned right is heard")
    func monoBusMixesBothSides() throws {
        let stereo = try Instrument(rate: 48_000, channels: 2), mono = try Instrument(rate: 48_000, channels: 1)
        let pan = try #require(Parameters.named("pan"))
        for instrument in [stereo, mono] {
            let synth = Synth(borrowing: try instrument.engine())
            synth.mode = .pads
            synth.setValue(100, of: pan, in: .pad(0))
            try instrument.midi(0x90, 36, 100)
        }
        let both = try stereo.render(seconds: 0.1), one = try mono.render(seconds: 0.1)
        #expect(one.count == 1)
        #expect(peak(both[0]) < 1e-6 && peak(both[1]) > 0.01)      // hard right
        #expect(peak(one[0]) > 0.005)
        #expect(zip(one[0], zip(both[0], both[1])).allSatisfy { abs($0 - ($1.0 + $1.1) / 2) < 1e-6 })
    }

    // MARK: The engine property and reset

    @Test("The engine property gives the engine the unit plays")
    func enginePropertyGivesTheEngine() throws {
        let instrument = try Instrument()
        var size: UInt32 = 0
        var writable: DarwinBoolean = true
        try #require(AudioUnitGetPropertyInfo(instrument.unit, AudioUnitPropertyID(kBrumleProperty_Engine), kAudioUnitScope_Global, 0,
                                              &size, &writable) == noErr)
        #expect(size == UInt32(MemoryLayout<UnsafeRawPointer>.size) && !writable.boolValue)

        let engine = try instrument.engine()
        let vowel = try #require(Parameters.named("vowel"))
        try instrument.setParameter("vowel", to: 1200)
        _ = try instrument.render()
        #expect(abs(brumle_get_plain(engine, Int32(BRUMLE_KEYBOARD_SET), Int32(vowel.index)) - 1200) < 0.5)
        #expect(try Instrument().engine() != engine)
    }

    @Test("Reset between renders silences the unit at its next render")
    func resetIsDeferred() throws {
        let instrument = try Instrument()
        try instrument.midi(0x90, 60, 100)
        #expect(peak(try instrument.render(seconds: 0.05)[0]) > 0.01)
        try #require(AudioUnitReset(instrument.unit, kAudioUnitScope_Global, 0) == noErr)
        let after = try instrument.render()
        #expect(peak(after[0]) == 0 && peak(after[1]) == 0)
        #expect(brumle_sounding_voices(try instrument.engine()) == 0)
    }
}
