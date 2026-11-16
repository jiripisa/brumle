# Phase 04 — The app and the Audio Unit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Brumle becomes playable: a standalone app (audio out, MIDI in, settings, an on-screen keyboard and pads) and an AUv2 instrument with the same panel, in the "Polar Khomus" look, with both modes, Send to pad and pad editing, validated by auval and described in the manual in English and Czech.

**Architecture:** Didgeridoo's, target for target (`.superpowers/didgeridoo-map.md` maps it; the files under `../Didgeridoo/Sources` are the pattern to mirror). `BrumleAU` (C++, vendored AudioUnitSDK) wraps the engine; `BrumleUI` is the shared SwiftUI panel over an `InstrumentModel` protocol; `Brumle` (app) and `BrumleAUView` (plug-in window) each implement the protocol. New logic goes into `BrumleCore`, test first.

**Tech Stack:** Swift 6.2 / SwiftPM, C++23, AudioUnitSDK (Apache-2.0, vendored), SwiftUI on macOS 26 with Liquid Glass (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`), AVAudioEngine, CoreMIDI, Swift Testing.

**Spec:** `.planning/specs/2026-11-15-engine-design.md` (§7 modes, §9 architecture, §10 panel, §11 phase 3). Mockups: `.planning/design/concepts/concept-2-keyboard.png`, `concept-2-pads.png`. Artwork: `Resources/Art/` (phase 03).

## Global Constraints

- macOS 26 minimum; SwiftPM only — never an Xcode project. Core target `BrumleCore` (never `brumle`).
- `BrumleCore` has no SwiftUI/AppKit. `BrumleUI` holds the panel; the app and the AU view stay thin.
- Audio thread: no allocation, locks, logging or I/O. The AU's `Reset` uses `brumle_request_reset`.
- `#pragma clang fp contract(off)` stays at the top of every engine `.cpp`; the 24 regression references and the prototype equivalence must stay green and bit-identical (engine sound does not change in this phase).
- Identity is permanent from the first release: AU type `aumu`, subtype `Brml`, manufacturer `JPis`, AU bundle id `io.jp4.brumle.audiounit`, view class `BrumleAUViewFactory`, factory `BrumleAUFactory`; AU parameter ID = engine parameter index (0…80), keyboard set only.
- Palette (spec §10): midnight `#111C29`, slate `#24374A`, icy silver `#CBDCE4`, bone `#E9DEC4`, aurora cyan `#67D6D3`. LFO 1 colour aurora cyan, LFO 2 bone, VEL icy silver.
- No text is baked into art; every label and value is live text. SF Pro for controls; the wordmark and section titles use a serif (`.serif` design, semibold).
- Every user-visible change: a line under `## Unreleased` in `CHANGELOG.md`; the manual describes every control, in `docs/manual.html` and `docs/cs/manual.html` alike (tag for tag).
- Commits in English, conventional style, no AI attribution. `git status` before every commit. Never push.

## Decisions taken for this phase [call — the author reviews them on return]

1. **AU parameters = the keyboard set** (81, IDs = engine indices). Clumps: the five sections (Reed, Stroke, Mouth, Breath, Master + LFO knobs as in the engine's sections); LFO and VEL amounts get no clump. Factory presets = the seven programs (they load into the keyboard set; Octave untouched).
2. **Saved state:** the base ClassInfo carries the keyboard set; an extra key `"brumle-pads"` carries a CFDictionary: `mode` (int), and `pads` — an array of 16 dictionaries `{note, group, program, values}` where `values` is CFData of Float32 plain values by parameter index. A shorter list covers the first N parameters (the table only grows at its end); a missing key leaves the pads alone (the default kit).
3. **The plug-in window reaches the engine directly.** A custom property `kBrumleProperty_Engine = 64001` (Global, read-only) returns the `BrumleEngine*` of the instance. The view wraps it in a non-owning `Synth`. Keyboard-set edits still go through `AUParameterSet` + gesture events (so hosts record automation and the render loop's parameter poll stays the authority); pad sets, pad notes, groups, the mode and on-screen pad/key hits go straight to the engine (they are not AU parameters). After a pad/mode edit the AU posts a `kAudioUnitProperty_ClassInfo` change so the host marks the project dirty.
4. **Latency and tail:** the AU reports `brumle_latency` frames as seconds (`GetLatency`), `SupportsTail` true and a tail of 15 s (the longest Ring).
5. **Output:** always stereo for {0,2}; for a mono bus {0,1} the AU renders stereo into a scratch buffer allocated in `Initialize` and writes (L+R)/2.
6. **Pad hit lights:** the engine gains `int brumle_pad_hits(const BrumleEngine*, int pad)` — a relaxed atomic counter incremented when a pad is triggered (MIDI or on-screen). The panel polls it every 40 ms and flashes the pad (cyan glow, 150 ms). No sound change.
7. **Pad names** are the name of the program last loaded into the pad's set ("Khomus"). Kits with own names come in phase 05.
8. **Header in this phase:** wordmark + emblem, Program menu, mode switch (Keyboard | Pads), LFO 1, LFO 2, VEL. The Preset menu and the MIDI (learn) button arrive in phase 05; the header leaves room for them.
9. **Send to pad:** a glass button in the keyboard-mode footer opens a popover with a 4 × 4 grid of the pads (number + name + pitch). Clicking one asks inline in the popover: "Replace pad 05 · Khomus with the keyboard's sound at C3?" [Replace] [Cancel] (the pitch is the last played note, C2 if none). No modal alert (alerts misbehave in plug-in windows).
10. **Pad editing:** in pad mode, a single click on a pad selects it and plays it (velocity from the vertical click position, as Didgeridoo's `KeyStrip`); the knobs then show and edit that pad's set; the Program menu loads into it. The lower-right inspector shows "Selected: 05 · Khomus", a pitch stepper/menu (C-1…G9, shown as note names) and a Group menu (Off, 1–16).
11. **Window size:** 1100 pt wide, height to fit (≈ 690 pt), like Didgeridoo. Same layout in app and plug-in; the app's footer additionally holds the on-screen keyboard (three octaves C2–B4) in keyboard mode; in the plug-in the keyboard-mode footer shows the khomus art, the "Send to pad" button and a smaller keyboard strip too (spec: Send to pad needs a last note; clicking keys there plays the engine through the pointer).
12. **The app installs the component** to `~/Library/Audio/Plug-Ins/Components/` from Settings (Didgeridoo's flow), never automatically.

## Review Focus

1. **Host reopens a project:** pads, groups, notes and mode come back exactly; an older/shorter `values` blob does not corrupt later parameters. → `AudioUnitTests.stateRoundTrip`, `stateShorterValues`.
2. **Automation vs. the panel:** a host-set keyboard parameter shows in the panel within 40 ms and a knob drag records begin/end gestures. → `AudioUnitWindowTests.hostChangeShows`, `dragIsHeardByTheHost`.
3. **Pad mode edits never leak into the keyboard set** (and vice versa), including Program loads and double-click resets. → `InstrumentModelTests.padEditsStayInPad` (app model and AU model).
4. **Sample-rate changes and mono hosts:** prepare at 44.1/48/96 kHz reports the right latency; a mono bus gets (L+R)/2, not silence for right-panned pads. → `AudioUnitTests.latencyFollowsRate`, `monoBusMixesBothSides`.
5. **The plug-in window in a host without the component bundle** (tests, hand registration) still opens (art missing → plain colours) and never crashes. → `AudioUnitWindowTests.windowWithoutArt`.

---

### Task 1: Engine and core additions

**Files:**
- Modify: `Sources/BrumleDSP/include/BrumleDSP.h`, `Sources/BrumleDSP/BrumleEngine.cpp` (pad hit counters only)
- Modify: `Sources/BrumleCore/Synth.swift` (`padHits(_:)`, a non-owning initialiser)
- Create: `Sources/BrumleCore/SynthState.swift`, `Sources/BrumleCore/Notes.swift`, `Sources/BrumleCore/KeyStrip.swift`, `Sources/BrumleCore/StandaloneSettings.swift`
- Test: `Tests/BrumleCoreTests/SynthStateTests.swift`, `NotesTests.swift`, `KeyStripTests.swift`, additions to `EngineTests.swift`

**Interfaces (produced):**
- C: `int brumle_pad_hits(const BrumleEngine*, int pad);` — 0 for a bad pad or engine.
- `Synth.init(borrowing engine: OpaquePointer)` — wraps an engine it does not own (no prepare, no destroy in deinit).
- `Synth.padHits(_ pad: Int) -> Int`.
- `public struct SynthState: Codable, Equatable` with `mode: PlayMode` (Codable via raw value), `keyboard: SetState`, `pads: [PadState]` (16); `public struct SetState: Codable, Equatable { program: Int; values: [String: Float] }` (by parameter identifier, plain); `public struct PadState: Codable, Equatable { note: Int; group: Int?; set: SetState }`. `Synth.state: SynthState { get }` and `Synth.apply(_ state: SynthState)`: unknown identifiers are ignored, missing ones keep their current value; fewer than 16 pads leave the rest alone.
- `public enum Notes { static func name(_ note: Int) -> String /* 36 → "C2", 61 → "C♯3" */; static let range: ClosedRange<Int> = 0...127 }` — octave numbering with C2 = 36 (the spec's).
- `public enum KeyStrip { static func velocity(at y: Double, height: Double) -> Int }` — Didgeridoo's (`../Didgeridoo/Sources/DidgeridooCore/KeyStrip.swift`), clamped 1…127, top = soft.
- `StandaloneSettings.swift`: copy Didgeridoo's `MIDISourceChoice`, `MIDIChannelFilter`, `OutputChannels` (drop `Tempo`: Brumle has no tempo).

- [ ] Step 1: Tests first — `EngineTests.padHitsCount` (pad mode, note 36 twice and note 37 once → pad 0 = 2, pad 1 = 1, pad 2 = 0; keyboard mode notes do not count; bad pad → 0); `SynthStateTests.roundTrip` (set values in keyboard and pads 0/7/15, notes, groups incl. nil, mode; `state` → JSON → `apply` on a fresh Synth gives an equal `state`); `.unknownAndMissingKeys`; `.fewerPads`; `NotesTests` (36 "C2", 60 "C4", 61 "C♯4", 0 "C-1", 127 "G9"); `KeyStripTests` as Didgeridoo's. Run: `swift test` → fail.
- [ ] Step 2: Implement. The pad hit counter is incremented on the audio thread where a pad voice is started (`std::atomic<int>` per pad, relaxed); reset leaves it alone.
- [ ] Step 3: `swift test`, `swift test -c release` pass; the 24 regression references unchanged.
- [ ] Step 4: Commit `feat(core): synth state, note names and pad hit counters`.

### Task 2: The Audio Unit

**Files:**
- Create: `ThirdParty/AudioUnitSDK/` (copy `../Didgeridoo/ThirdParty/AudioUnitSDK` verbatim incl. `LICENSE.txt`)
- Create: `Sources/BrumleAU/BrumleAU.cpp`, `Sources/BrumleAU/include/BrumleAU.h`, `Sources/BrumleAUExports/Exports.c`, `Sources/BrumleAUExports/include/` (as Didgeridoo's), `Resources/AudioUnit-Info.plist`
- Modify: `Package.swift` (targets `AudioUnitSDK`, `BrumleAU`, `BrumleAUExports`, dynamic product `BrumleAU` = BrumleAU + BrumleAUView + BrumleAUExports — `BrumleAUView` arrives in Task 6; until then the product lists BrumleAU + BrumleAUExports), test target depends on `BrumleAU`
- Test: `Tests/BrumleCoreTests/AudioUnitTests.swift`

**Pattern:** `../Didgeridoo/Sources/DidgeridooAU/DidgeridooAU.cpp` (map §2). Differences: decisions 1–5 above; no tempo/transport; no controllers property (phase 05); `kBrumleProperty_Engine = 64001` returns `BrumleEngine*` (size `sizeof(void*)`).

**Codes (`BrumleAU.h`):** `BRUMLE_AU_TYPE 'aumu'`, `BRUMLE_AU_SUBTYPE 'Brml'`, `BRUMLE_AU_MANUFACTURER 'JPis'`, `BRUMLE_AU_BUNDLE_ID "io.jp4.brumle.audiounit"`, `BRUMLE_AU_VIEW_CLASS "BrumleAUViewFactory"`, `kBrumleProperty_Engine 64001`, `extern "C" void* BrumleAUFactory(const AudioComponentDescription*)` declared for tests. `AudioUnit-Info.plist`: name "Jiri Pisa: Brumle", factoryFunction `BrumleAUFactory`, `sandboxSafe` true, tags [Synthesizer], `LSMinimumSystemVersion` 26.0.

- [ ] Step 1: Tests (register the unit in-process with `AudioComponentRegister`, test subtype `'Brmt'`, as Didgeridoo's `AudioUnitWindowTests` setup): `parametersAreTheKeyboardSet` (81 parameters, names/ranges/defaults = `Parameters.all`, clumps as decision 1); `noteRenders` (note-on via `MusicDeviceMIDIEvent` → non-silent stereo output within 100 ms at 48 kHz); `hostParameterReachesEngine` (`AudioUnitSetParameter` ring → engine set 0 after one render); `factoryPresetLoadsProgram` (preset 2 → keyboard set = program 2 values, Octave untouched); `stateRoundTrip` (set pad 3 values/note/group, mode pads → `ClassInfo` → fresh instance restores them); `stateShorterValues` (a `values` blob of 34 floats restores those and leaves 34…80 at the defaults); `latencyFollowsRate` (`kAudioUnitProperty_Latency` = 29/44100 at 44.1 kHz, 29/48000 at 48 kHz, 0 at 96 kHz); `monoBusMixesBothSides` (1-channel output, a pad with Pan +100 is audible); `enginePropertyGivesTheEngine` (64001 returns a pointer through which `brumle_get_plain` reads what `AudioUnitSetParameter` set after a render); `resetIsDeferred` (Reset during idle does not crash and silences after the next render).
- [ ] Step 2: Implement; `swift build` with no warnings in Brumle's own code.
- [ ] Step 3: `swift test`, `-c release`, `--sanitize=thread` pass.
- [ ] Step 4: Commit `feat(au): the Audio Unit instrument`.

### Task 3: The shared panel, part 1 — artwork, knobs, header, sections

**Files:**
- Create: `Sources/BrumleUI/Artwork.swift`, `InstrumentModel.swift`, `KnobView.swift`, `SectionView.swift`, `HeaderView.swift`, `InstrumentPanel.swift`
- Modify: `Package.swift` (target `BrumleUI` depends on `BrumleCore`)
- Test: `Tests/BrumleCoreTests/` — none for views; the model protocol's logic lives in Core (Task 1) and in the models (Tasks 5, 6).

**Interfaces:**
- `@MainActor public protocol InstrumentModel: AnyObject, Observable` — `var mode: PlayMode { get set }`, `var selectedPad: Int { get set }` (0…15), `var shownSet: SoundSet { get }` (keyboard in keyboard mode, `.pad(selectedPad)` in pad mode), `func program(in: SoundSet) -> Int`, `func loadProgram(_: Int, into: SoundSet)`, `func position(of: Parameter, in: SoundSet) -> Double` (0…1), `func setPosition(_: Double, of: Parameter, in: SoundSet)`, `func resetToDefault(_: Parameter, in: SoundSet)` (program value, else default), `func beginEditing(_: Parameter, in: SoundSet)`, `func endEditing(_: Parameter, in: SoundSet)`, `func padNote(_: Int) -> Int`, `func setPadNote(_: Int, pad: Int)`, `func padGroup(_: Int) -> Int?`, `func setPadGroup(_: Int?, pad: Int)`, `func padName(_: Int) -> String`, `func padHits(_: Int) -> Int`, `var lastNote: Int? { get }`, `func sendToPad(_: Int)`, `func hitPad(_: Int, velocity: Int)` (note-on 36 + pad; works only in pad mode, where notes 36–51 are the pads), `func releasePad(_: Int)` (note-off 36 + pad), `func keyDown(_: Int, velocity: Int)`, `func keyUp(_: Int)`, `func refresh()` (poll, called every 40 ms by the panel). Extension: `value(of:in:)`, `label(of:in:)`.
- `Artwork`: Didgeridoo's (`bundle`, images `background`, `khomus`, `logo`, `knob`, `ornament` from `Art/`), colours `midnight`, `slate`, `silver`, `bone`, `aurora`, `lfo(_:)`, `vel`; `View.instrumentBackground()` (art or midnight).
- `KnobView(parameter:, set:, model:, editing: KnobEditing)` where `KnobEditing` is `.value`, `.amount(lfo: Int)`, `.velocity` — Didgeridoo's KnobView behaviour (vertical drag 200 pt full range, Shift ×10 finer, double-click reset, begin/end editing, amount snap near 0, non-target knobs dimmed to 0.3 and not hittable) with Brumle's look: `knob.png` cap 44 pt, value arc aurora, LFO arcs in the LFO colour, VEL arc silver, name above (SF Pro 12 semibold, bone), value below (SF Pro 12 monospaced digits, silver). Choice parameters (Stroke, Key Up, Curve, LFO Start) are glass segmented pickers, LFO shapes a glass menu — never knobs.
- `HeaderView`: emblem (`logo.png`, 40 pt) + "Brumle" (serif 34 pt semibold, silver), Program `Menu` (glass), mode `Picker` (segmented, glass, Keyboard | Pads), LFO 1 / LFO 2 / VEL toggle buttons (glass; on = tinted in their colour; only one on at a time; on = knobs edit that source's amounts).
- `InstrumentPanel<Footer: View>(model:, footer:)` with `static let width: CGFloat = 1100`: header, an `ornament.png` strip, five section groups in one row (glass panels: `GlassEffectContainer`, `.glassEffect(.regular.tint(midnight.opacity(0.35)), in: .rect(cornerRadius: 16))`) in the order and column layout of the mockup (Reed 2 cols, Stroke 2 cols with pickers, Mouth 3 cols, Breath 2 cols, Master 3 cols), then the footer. A `.task` calls `model.refresh()` every 40 ms.

- [ ] Step 1: Implement; `swift build` clean.
- [ ] Step 2: A scratch preview program (scratchpad, not the repo) renders `InstrumentPanel` with a stand-in model into a PNG via `ImageRenderer`; compare with the mockup by eye: section order and positions, legibility of every name and value, nothing baked into art. Record what was checked in the report.
- [ ] Step 3: Commit `feat(ui): the panel's knobs, header and sections`.

### Task 4: The shared panel, part 2 — pads, keyboard, Send to pad, pad inspector

**Files:**
- Create: `Sources/BrumleUI/PadGridView.swift`, `PadInspectorView.swift`, `KeyboardStripView.swift`, `SendToPadView.swift`, `ModeFooterView.swift`

**Interfaces:**
- `ModeFooterView(model:)` — the panel's footer for both front ends: keyboard mode → `khomus.png` over an ornament band, "Keyboard" (serif), "Send to pad" glass button + popover (`SendToPadView`), and `KeyboardStripView` (C2–B4, white keys bone, black keys midnight; C2/C3/C4 labels; mouse down = `keyDown` with `KeyStrip.velocity`, up/drag-out = `keyUp`; held key tinted aurora); pad mode → `PadGridView` (left, 4 × 4, pad 1 top-left as in the approved mockup (not bottom-left as on an MPC), numbered 01…16; mouse down = `hitPad` (note-on 36 + pad, velocity from `KeyStrip`, and selects the pad), mouse up = note-off 36 + pad; each showing number + name (serif) and pitch + group ("C2  G1", "Off" when no group) in glass tiles; selected pad aurora outline; a hit flashes the tile for 150 ms via `padHits`) and `PadInspectorView` (right: khomus art, "Pads", "Selected: 05 · Khomus", pitch menu (note names), Group menu (Off, 1…16)).
- `SendToPadView`: decision 9.
- [ ] Step 1: Implement; `swift build` clean.
- [ ] Step 2: Scratch preview PNGs of both modes; check against the mockups; report.
- [ ] Step 3: Commit `feat(ui): pads, keyboard, Send to pad and the pad inspector`.

### Task 5: The app

**Files:**
- Create: `Sources/Brumle/AppModel.swift`, `AudioOutput.swift`, `MIDIInput.swift`, `SettingsView.swift`
- Modify: `Sources/Brumle/BrumleApp.swift`, `ContentView.swift`; `Package.swift` (app depends on `BrumleUI`)
- Test: `Tests/BrumleCoreTests/AppModelLogicTests.swift` only for logic moved into Core; the model itself is exercised by Task 7's checks.

**Pattern:** `../Didgeridoo/Sources/Didgeridoo/*` (map §5). `AppModel: InstrumentModel` over an owning `Synth`; persists `synth.state` (JSON) in UserDefaults key `synthState` on every edit (debounced 0.5 s) and restores it at launch; settings keys as Didgeridoo's minus tempo. `AudioOutput` and `MIDIInput` (virtual destination "Brumle") copied with Brumle names. `SettingsView`: MIDI source and channel, audio device and channel pair, "Audio Unit plug-in" status + "Install Audio Unit" (decision 12). Window: `Window("Brumle", id: "main")`, not resizable, `InstrumentPanel(model:) { ModeFooterView(model:) }`, a gear button for Settings in the header's trailing slot, Sparkle's "Check for Updates…" kept.

- [ ] Step 1: Implement; `swift build` clean; `./run.sh` launches (by path), a click on a key sounds (system output), a click on a pad sounds and selects it, Send to pad works, quit and relaunch restores the edits.
- [ ] Step 2: `swift test` passes.
- [ ] Step 3: Commit `feat(app): the standalone app plays Brumle`.

### Task 6: The plug-in window and build.sh

**Files:**
- Create: `Sources/BrumleAUView/AudioUnitModel.swift`, `AudioUnitWindow.swift`
- Modify: `Package.swift` (target `BrumleAUView` → `BrumleCore`, `BrumleUI`; product `BrumleAU` gains it; tests depend on it), `build.sh` (component assembly, `Resources/Art` into the app and the component, signing inside-out — Didgeridoo's `build.sh` l.70–105, 158–185), `development_workflow.md` (auval line), `CLAUDE.md` (the AU identity rule)
- Test: `Tests/BrumleCoreTests/AudioUnitWindowTests.swift`

**Pattern:** `../Didgeridoo/Sources/DidgeridooAUView/*` (map §3). `AudioUnitModel: InstrumentModel` over the `AudioUnit`: keyboard-set reads/writes via `AudioUnitGetParameter`/`AUParameterSet` + gesture events, programs via `kAudioUnitProperty_PresentPreset`; everything else through the borrowed engine (decision 3). The factory sets `Artwork.bundle = Bundle(for: BrumleAUViewFactory.self)`.

- [ ] Step 1: Tests: `knobSetsParameter`, `hostChangeShows`, `choosingAProgram`, `dragIsHeardByTheHost`, `padEditsStayInPad` (pad-mode knob edits change the engine's pad set, not AU parameter values), `sendToPadFromWindow`, `windowWithoutArt` (model + `NSHostingView` built without the component bundle).
- [ ] Step 2: Implement; `./build.sh debug` and `./build.sh release` produce `Brumle.app/Contents/PlugIns/Brumle.component` with art in both; `codesign --verify --deep --strict` passes.
- [ ] Step 3: Copy the release component to `~/Library/Audio/Plug-Ins/Components/`, run `auval -v aumu Brml JPis` → "AU VALIDATION SUCCEEDED" with "Cocoa Views Available: 1"; record the output summary. A scratch minimal host (scratchpad) opens the plug-in's window and saves a picture.
- [ ] Step 4: `swift test`, `-c release`, `--sanitize=thread` pass. Commit `feat(au): the plug-in window and the component bundle`.

### Task 7: Manual, website, verification

**Files:**
- Modify: `docs/manual.html`, `docs/cs/manual.html`, `docs/index.html`, `docs/cs/index.html`, `docs/assets/brumle-window.png`, new `docs/assets/manual/*.png`, `CHANGELOG.md`
- Create: `.planning/phases/04-app-and-audiounit/VERIFICATION.md`; update `.planning/ROADMAP.md`, `.planning/STATE.md`

- [ ] Step 1: Screenshots of the real app window (keyboard and pad mode) with `screencapture -x -o -l <window id>` (`~/.claude/skills/new-macos-app/scripts/window_id.swift`), and the plug-in window from the scratch host.
- [ ] Step 2: Manual (EN, then CS tag for tag): getting started (app, MIDI, audio, installing the plug-in), the header, every knob by section (what it does, range), the two modes, pads (selecting, pitch, group, mute groups), Send to pad, LFO 1/2 and VEL amounts on the knobs, the plug-in in a host (automation = keyboard set only; pads saved with the project). Figures with numbered marks (`docs/assets/manual.css`).
- [ ] Step 3: CHANGELOG lines (the app plays; the Audio Unit; both modes; Send to pad; pad editing; installing the plug-in).
- [ ] Step 4: VERIFICATION.md with real output (tests ×3, builds, codesign, auval, the app run by hand through MIDI if a device is present, else on-screen only), ROADMAP (04 ✅, 05 next), STATE. Commit `docs: manual and verification for phase 04`.
