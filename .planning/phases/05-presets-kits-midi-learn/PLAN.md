# Phase 05 — Presets, kits and MIDI learn Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Brumle gets the rest of Didgeridoo's feature parity:
- user presets (a sound saved as a file and loaded into the keyboard or into a pad);
- kits (all sixteen pads saved and loaded as one file);
- a MIDI controller on every keyboard knob, with MIDI learn.

The app and the plug-in share the files.

**Architecture:** Didgeridoo's pattern (`../Didgeridoo/Sources/DidgeridooCore/{Presets,Controllers}.swift`, the controller map in `../Didgeridoo/Sources/DidgeridooDSP/DidgeridooEngine.cpp` around `kStandardController`, `controller_`, `learn`, `changes`). Map: `.superpowers/didgeridoo-map.md`.
- The engine owns the controller map and the learn state; a CC moves keyboard-set knobs on the audio thread.
- Core owns the file libraries.
- Both models (`AppModel`, `AudioUnitModel`) implement the new protocol members.
- The panel adds a Preset menu, a MIDI button, controller editing on the knobs and a Kit menu.

**Tech Stack:** as phase 04.

**Spec:** `.planning/specs/2026-11-15-engine-design.md`:
- §2: feature parity with Didgeridoo.
- §7: kits saved and loaded like presets, shared as files.
- §9: MIDI controllers per keyboard-set knob with learn; user presets as files.
- §10: program, preset and kit menus; MIDI learn as in Didgeridoo.
- §11: phase 4 in that section's numbering.

Carried from phase 04's final review (`.planning/phases/04-app-and-audiounit/VERIFICATION.md`): M6, M3, M7 and M10.

## Global Constraints

Phase 04's constraints still hold, verbatim:
- SwiftPM only. `BrumleCore` has no UI.
- The audio thread does no allocation, locks, logging or I/O.
- `#pragma clang fp contract(off)`. The 24 regression references and the prototype equivalence stay bit-identical; the sound does not change.
- The AU identity is permanent: parameter IDs 0…80, the keyboard set only.
- Every user-visible change gets a CHANGELOG line, and the manual is updated in English and Czech, tag for tag.
- Commits are in English, with no AI attribution and no push.

New in this phase:
- The file formats are JSON and decode tolerantly: a missing field takes its default and an unknown field is ignored. A file written by a later version must still load.
- The folders are `~/Library/Application Support/Brumle/Presets/*.brumle` and `~/Library/Application Support/Brumle/Kits/*.brumlekit`. The app and the plug-in share them; they are created lazily.
- Names follow Didgeridoo's `PresetLibrary.cleaned`: trimmed, at most 60 characters, no `/` or `:`, not empty.

## Decisions taken for this phase [call — the author reviews them on return]

1. **A preset is one knob set.** It holds a `SetState`: program, values and the preset's own name. It loads into the set the panel shows: the keyboard set in keyboard mode, the selected pad in pad mode. The Preset menu lists the files and offers "Save as…" and "Delete".
2. **"Preset in use" is per set.** Each of the 17 sets remembers the preset it came from: an optional `preset` name in `SetState`, saved with the app state and the AU state.
   - Double-click reset goes to the preset's value while that file exists. Otherwise it goes to the program's value, then to the default (Didgeridoo's `PresetShelf` rule).
   - Loading a program clears the set's preset.
3. **A kit is all 16 pads** (`[PadState]`) plus its name. The Kit menu lives in the pad inspector (pad mode) and offers:
   - the kit files;
   - "Default kit" (the engine's);
   - "Save kit as…";
   - "Delete kit".

   Loading a kit replaces all 16 pads. The mode and the keyboard set are untouched.
4. **Pad names:** the set's preset name if it has one, otherwise its program's name, otherwise "Custom".
5. **MIDI controllers are on the keyboard set's 34 knobs only.** Amounts and pads get none.
   - Every knob comes with a standard controller. Use the GM meaning where one fits:
     - Volume 7, Pan 10;
     - Vowel 74 (brightness), Reso 71 (timbre);
     - Ring 72 (release time), Breath 2 (breath controller);
     - Vel Sens 73 (attack).
   - Every other knob takes a number from the undefined ranges 14–31, 85–90 and 102–119, in table order.
   - Reserved, and never given to a knob: CC 0–1, 6, 32, 38, 64, 96–101 and 120–127. CC 1 is the mod wheel, which moves Close.
   - A CC puts its knob where its value says: 0 is the bottom of the travel, 127 the top, and 64 the middle of a bipolar knob.
   - One controller serves one knob.
   - In pad mode a CC still moves the keyboard set. This is stated in the manual.
6. **Learn:** the MIDI button in the header switches the knobs into controller editing (`KnobEditing.controller`), as in Didgeridoo.
   - A knob shows its CC instead of its value.
   - A click starts listening (dashed ring, "move a control"). The next CC that moves is taken.
   - Double-click restores the standard CC.
   - The context menu offers "No controller" and "Back to CC nn".
   - Choice controls (pickers) can learn too. The CC's value is mapped across the choices.
7. **The controller map is per instance, not per sound.**
   - The app keeps it in UserDefaults (`controllers`, a `ControllerMap` by identifier).
   - The AU keeps it in its state (`brumle-controllers`: CFData of SInt32 per knob, -1 for none; a shorter list covers the first N).
   - Loading a preset or a kit does not change it.
8. **Engine-side changes are mirrored.** A CC that moves a knob, or a learn, bumps `brumle_changes`.
   - The AU's `Render` then mirrors the keyboard set's engine values into its parameters with `SetParameterRT(i, v, true)`, as Didgeridoo does, so hosts and the window see them.
   - The app model's `refresh()` reads values and controllers again when the counter moved.
9. **Missing knobs (M6).** When a `SetState` that lacks some knobs is applied (an older file or state), those knobs take the value of the state's program. Unknown identifiers are ignored. This replaces phase 04's "keep the current value" rule.
10. **The plug-in window reopens on the selected pad (M3).** `selectedPad` is saved in `brumle-pads`. The AU announces latency changes with `PropertyChanged(kAudioUnitProperty_Latency)` when `Initialize` moves it, and reports latency before the first Initialize (M7). Knobs get a VoiceOver adjustable action (M10).

## Review Focus

1. **A preset or kit file from another version, or damaged.** Missing fields are defaulted, unknown fields ignored, wrong types reported as an error in the menu, never a crash. → `PresetFileTests.tolerant`, `.damaged`.
2. **Two plug-in instances and the app share the folders.** One saves, the others see the new name the next time their menu opens; deleting the preset in use falls back to the program value. → `PresetLibraryTests.sharedFolder`, `AudioUnitWindowTests.presetsOfAnotherWindow`.
3. **A CC storm.** A controller moving every block while the host automates the same knob: neither crashes nor races. The last writer wins and the window shows it within 40 ms. → `EngineTests.controllerMovesKnob`, `AudioUnitTests.controllerMirrorsToHost`, TSan.
4. **Learn while the window closes, or while the mode switches.** Learning is cancelled cleanly and no knob is left listening. → `AudioUnitWindowTests.learnCancelledOnClose`.
5. **Project reopen.** Controllers, selectedPad and the presets in use come back. An older project without these keys keeps the standard controllers and pad 01. → `AudioUnitTests.stateKeepsControllersAndSelection`, `.olderStateKeepsDefaults`.

---

### Task 1: Engine controllers and learn

**Files:**
- Modify: `Sources/BrumleDSP/include/BrumleDSP.h`, `Sources/BrumleDSP/BrumleEngine.cpp` (plus `Params.cpp/.h` if the standard table lives with the parameters)
- Create: `Sources/BrumleCore/Controllers.swift`
- Test: `Tests/BrumleCoreTests/ControllerTests.swift`, additions to `EngineTests.swift`

**Interfaces (C, mirroring Didgeridoo's names):**
- `brumle_standard_controller(int param)` returns -1 for none.
- `brumle_controller_reserved(int cc)`.
- `brumle_get_controller(engine, param)`.
- `brumle_set_controller(engine, param, cc)`: -1 removes it; a reserved CC is not taken; a CC already in use moves to the new knob.
- `brumle_reset_controllers(engine)`.
- `brumle_learn(engine, param)`: -1 cancels.
- `brumle_learning(engine)`.
- `unsigned brumle_changes(engine)`.

**Engine behaviour:**
- The controller map is atomic per knob (`int8_t`).
- A CC on any channel moves keyboard-set knob `param` to normalised `cc/127`, or exactly the middle for 64 on a bipolar knob.
- The CC is applied at its sample offset in the MIDI event order, like the other MIDI events.
- A CC that moves a knob, or completes a learn, bumps `changes` (a relaxed atomic).
- CC 1 (mod wheel), 121 and 123 keep their phase-02 meanings.

**Swift:**
- `Controllers.standard(for:)`, `isReserved`, `label`.
- `Synth.controller(of:)`, `setController(_:of:)`, `resetControllers()`, `learning`, `learn(_:)`, `changes`.
- `ControllerMap: Codable` (by identifier, tolerant), with `init(capturing:)` and `apply(to:)`.

- [ ] Tests first:
  - `ControllerTests`:
    - every knob has a standard CC;
    - no two share one;
    - none is reserved;
    - the amounts have none;
    - the GM ones are as decision 5 says.
  - `EngineTests.controllerMovesKnob`:
    - CC 74 = 127 puts Vowel at the top of its travel;
    - CC 64 on a bipolar knob puts it at the middle;
    - `changes` rises;
    - pad sets are unchanged.
  - `.learnTakesNextCC`.
  - `.reservedNotTaken`.
  - `.oneControllerOneKnob`.
  - `.sameSoundWithoutCC`: the 24 references are unchanged.
- [ ] Implement. Then `swift test`, `swift test -c release` and `swift test --sanitize=thread`.
- [ ] Commit `feat(dsp): MIDI controllers on the knobs, with learn`.

### Task 2: Preset and kit files

**Files:**
- Create: `Sources/BrumleCore/Presets.swift`, `Sources/BrumleCore/Kits.swift`
- Modify: `Sources/BrumleCore/SynthState.swift`:
  - `SetState.preset: String?`;
  - the apply rule of decision 9.
- Test: `PresetLibraryTests.swift`, `PresetFileTests.swift`, `KitTests.swift`, additions to `SynthStateTests.swift`

**Interfaces:**
- `PresetError`.
- A generic `FileLibrary<Content: Codable>`, with:
  - `init(folder:fileExtension:)`;
  - `names()`, sorted case-insensitively;
  - `cleaned(_:)`;
  - `save(_:as:) throws -> String`;
  - `load(_:) throws -> Content`;
  - `delete(_:)`, which moves the file to the Trash (`FileManager.trashItem`) unless the library is made with `deletesForGood: true` (tests);
  - `makeFolder()`.
- `PresetLibrary = FileLibrary<SetState>` with `.standard` (Presets, `brumle`).
- `KitLibrary = FileLibrary<Kit>` with `.standard` (Kits, `brumlekit`).
- `public struct Kit: Codable, Equatable { name: String; pads: [PadState] }`, decoding tolerantly.
- `PresetShelf`, Didgeridoo's, per set:
  - `value(of:)` gives the preset's value or nil;
  - `inUse` counts only while the file exists.
- `Synth.apply(_ set: SetState, to: SoundSet)`.
- `Synth.kit: Kit` and `apply(_ kit: Kit)`.
- `PadLabel.name(program:preset:)`, following decision 4.

- [ ] Tests first:
  - round trips;
  - names: cleaning, collision, a 60-character limit;
  - `sharedFolder`: two libraries on one temporary folder;
  - `tolerant`: missing and unknown fields;
  - `damaged`: not JSON, so an error is thrown;
  - delete to the Trash, run in a temporary folder with `deletesForGood: true`;
  - decision 9: a 30-knob state takes the program's values for the rest;
  - kit apply leaves the mode and the keyboard set alone.
- [ ] Implement. `swift test`.
- [ ] Commit `feat(core): preset and kit files`.

### Task 3: The AU keeps controllers, presets in use and the selected pad

**Files:** `Sources/BrumleAU/BrumleAU.cpp`, `Tests/BrumleCoreTests/AudioUnitTests.swift`

- [ ] Tests first:
  - `controllerMirrorsToHost`: a CC sent with `MusicDeviceMIDIEvent` moves the engine knob, and after one render `AudioUnitGetParameter` shows it. An AU parameter listener is notified.
  - `hostAndControllerTakeTurns`: Didgeridoo's.
  - `stateKeepsControllersAndSelection`: `brumle-controllers`; `selectedPad`; `keyboardPreset`; each pad's `preset`.
  - `olderStateKeepsDefaults`.
  - `latencyAnnounced`: a property listener on Latency fires when Initialize changes the rate's latency. Latency is non-zero before the first Initialize at 44.1 kHz.
- [ ] Implement:
  - the Render mirror, when `brumle_changes` moved;
  - SaveState and RestoreState: tolerant, bounded, every CF type checked, as in phase 04;
  - `PropertyChanged(Latency)`.
- [ ] `swift test` ×3. auval is run by the controller.
- [ ] Commit `feat(au): controllers, presets in use and the selected pad are saved with the project`.

### Task 4: The panel: Preset menu, MIDI learn, Kit menu

**Files:**
- `Sources/BrumleUI/InstrumentModel.swift`
- `HeaderView.swift`
- `KnobView.swift` / `KnobEdit.swift`
- `SectionView.swift` (choices learning)
- `PadInspectorView.swift`
- new `NameSheetView.swift`: a popover with a text field, Save and Cancel, and the name rules from Core; no modal sheet in plug-in windows.

**Protocol additions:**
- `presets: [String]`, `presetInUse(in: SoundSet) -> String?`, `loadPreset(_:into:) throws`, `savePreset(as:from:) throws`, `deletePreset(_:) throws`, `lookAtPresets()`;
- `kits: [String]`, `loadKit(_:) throws`, `loadDefaultKit()`, `saveKit(as:) throws`, `deleteKit(_:) throws`;
- `controller(of:) -> Int?`, `setController(_:of:)`, `resetControllers()`, `learning: Parameter?`, `learn(_:)`;
- `editing` gains a controller mode: the header's MIDI button, mutually exclusive with LFO 1, LFO 2 and VEL.

**Look:**
- The Preset menu goes in the header beside Program (as in the mockup) and shows the shown set's preset in use, or "—".
- The MIDI button sits after VEL. It uses icy silver while on.
- The Kit menu is in the pad inspector under "Pads".
- An error from a file shows as a one-line message under the menu for 4 s, never as an alert.
- Knobs get `.accessibilityAdjustableAction` (M10).

- [ ] Logic you can test (menu entries, the name check, the controller-mode knob label) goes in Core or small types first, with tests.
- [ ] Preview PNGs in the scratchpad: the header with Preset and MIDI, controller mode, the listening knob, and the pad inspector with Kit.
- [ ] Commit `feat(ui): presets, kits and MIDI learn in the panel`.

### Task 5: Both models

**Files:** `Sources/Brumle/AppModel.swift`, `Sources/BrumleAUView/AudioUnitModel.swift`, `AudioUnitWindow.swift`, tests `AudioUnitWindowTests.swift`, Core tests for the app's logic.

**App:**
- Controllers persist in UserDefaults (`controllers`).
- The presets in use ride in `synthState`.
- `refresh()` reads values and controllers when `changes` moved, and calls `lookAtPresets` when a menu opens.

**AU model:**
- Controllers, learning and presets go through the engine pointer. Then set 64002.
- The keyboard set's preset load goes through `AUParameterSet` per value, plus one `everythingMoved` notify, so hosts see it.
- Learning is cancelled on window close.
- The window opens on the AU's saved `selectedPad`. Since the AU owns it, add `kBrumleProperty_SelectedPad = 64003` (read/write UInt32) to the AU and use it.

- [ ] Tests:
  - `windowSavesAndLoadsAPreset`;
  - `resetReturnsThePresetsValue`;
  - `projectBringsThePresetBack`;
  - `presetsOfAnotherWindow`;
  - `deletingAPreset`;
  - `windowLearns`;
  - `learnCancelledOnClose`;
  - `kitRoundTrip`;
  - `windowReopensOnSelectedPad`.

  Each uses temporary folders: make the libraries injectable.
- [ ] `swift test` ×3, `./build.sh release`, codesign.
- [ ] Commit `feat: presets, kits and MIDI learn in the app and the plug-in`.

### Task 6: Manual, CHANGELOG, verification

- [ ] Manual, in English and Czech, tag for tag:
  - the Preset menu: save, load into the keyboard or a pad, delete, reset to the preset's value;
  - kits;
  - MIDI controllers and learn, with the full standard-CC table and the reserved CCs;
  - CCs in pad mode move the keyboard set;
  - pad names.
- [ ] Pictures are renders as in phase 04, unless the screen is unlocked; then use real `screencapture`.
- [ ] CHANGELOG lines.
- [ ] `VERIFICATION.md` with real runs and an honest not-verified list.
- [ ] Update ROADMAP (05 ✅, 06 release next) and STATE.
- [ ] Commit `docs: manual and verification for phase 05`.
