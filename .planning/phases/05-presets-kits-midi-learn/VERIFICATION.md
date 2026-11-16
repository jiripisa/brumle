# Phase 05 — Verification (2026-11-16)

Brumle has user presets (one sound, loaded into the keyboard or a pad), kits (all sixteen pads),
a MIDI controller on every knob and switch of the keyboard's sound with learn, and an Audio Unit
that saves the controllers, the presets in use and the selected pad with the project. The app
and the plug-in share the preset and kit folders. The screen of this Mac stayed locked, so no
real host, MIDI hardware or audio device was used (see "Not verified"); the app itself was driven
from inside the running debug build.

The checks below ran on `9d18393`. The final review's fix wave (`57228c5`…`5a78862`) changed
code again, and was re-checked on `5a78862`: `swift test`, `swift test -c release` and
`swift test --sanitize=thread` each passed 275 tests, `./build.sh release` succeeded, and
`codesign --verify --deep --strict` passed.

| Check | Result |
|---|---|
| `swift test` | `✔ Test run with 272 tests in 33 suites passed after 5.541 seconds.` No `warning:` or `✘` lines; the one opt-in test "Writes the listening renders" is skipped, as before |
| `swift test -c release` | `✔ Test run with 272 tests in 33 suites passed after 1.625 seconds.` The 24 regression references and the prototype equivalence hold, so the sound is unchanged |
| `swift test --sanitize=thread` | `✔ Test run with 272 tests in 33 suites passed after 45.510 seconds.` No ThreadSanitizer report |
| `./build.sh debug`, `./build.sh release` | both end with `Build complete: …/build/{debug,release}/Brumle.app`, no `warning:`; each app holds `Contents/PlugIns/Brumle.component` |
| `codesign --verify --deep --strict build/release/Brumle.app` | `valid on disk`, `satisfies its Designated Requirement` |
| `nm -gU …/Brumle.component/Contents/MacOS/Brumle` | one symbol: `T _BrumleAUFactory` |
| `auval -v aumu Brml JPis` (run by the controller, on the `a302b08` build) | `AU VALIDATION SUCCEEDED.` 81 parameters PASS; `Cocoa Views Available: 1` (`BrumleAUViewFactory`); `Component Version: 0.1.0 (0x100)`. The controller installed the component into `~/Library/Audio/Plug-Ins/Components/` for this |
| Review focus 1, a damaged or later file | `PresetFileTests.tolerant`, `.damaged`, `badProgram`, `badPad`, `controlCharacters` pass: missing fields take defaults, unknown ones are ignored, bad program, note and group numbers are refused without a trap, a file that is not JSON throws |
| Review focus 2, shared folders | `PresetLibraryTests.sharedFolder`, `AudioUnitWindowTests.presetsOfAnotherWindow`, `deletingAPreset` pass; the in-app drive saw a file written by another library appear when the menu opened (below) |
| Review focus 3, a CC storm | `EngineTests.controllerMovesKnob` (a storm on every CC in pad mode leaves the 16 pad sets bit-identical), `AudioUnitTests.controllerMirrorsToHost`, `hostAndControllerTakeTurns`, `controllerWinsWithinTheBlock`, `ThreadTests.controlWhileRendering` (random CCs, controller sets, learns and resets while rendering) pass, also under TSan |
| Review focus 4, learn while closing or switching | `AudioUnitWindowTests.learnCancelledOnClose`, `windowLearns` pass; the in-app drive saw learning cancelled by a mode switch, MIDI off, LFO 1 on and resign active |
| Review focus 5, project reopen | `AudioUnitTests.stateKeepsControllersAndSelection`, `stateControllersAreChecked`, `olderStateKeepsDefaults`, `presetNamesAreSeventeen`, `presetNamesAreCapped`, `presetNamesWhileSaving`, `AudioUnitWindowTests.projectBringsThePresetBack`, `windowReopensOnSelectedPad` pass |
| M7, latency | `AudioUnitTests.latencyAnnounced`: non-zero latency before the first Initialize; the listener fires only on a change across 48 → 48 → 96 → 192 → 44.1 kHz |
| The sound with controllers unused | `EngineTests.sameSoundWithoutCC`: CCs nobody listens to, a changed and reset map and a cancelled learn render bit-identical to a plain engine |
| The app, driven inside the running app (Tasks 4 and 5) | a scratch hook, never committed, hosted the real `ContentView` and `AppModel` in a borderless window inside the debug app, on temporary folders, with synthesized clicks. Saving a preset ticks it; Send to pad gives pad 05 the keyboard's preset name; a program load clears only that set's preset; the Preset and Kit menus read the folder as they open (a file written by another library appears, and does not without opening); a missing file shows "There is no “Not there” in the folder any more." under the menus at 2.3 s and is gone at 4.6 s; with MIDI on, clicking Vowel makes it listen, CC 50 = 100 is learnt and moves Vowel to 2209 Hz; the Curve switch learns CC 51 and 127 gives Step; a second click stops listening; LFO 1 on, MIDI off, resign active and Keyboard → Pads each cancel learning; a pad's controls in MIDI mode do not learn; a kit saved, the default kit loaded and the kit loaded back restore pad 05's preset; a relaunch brings back the presets in use and the learnt CC 50 and 51 |
| The AU model (Task 5) | `AudioUnitWindowTests`: the nine window tests from the plan plus `presetLoadIsHeard` (one AnyParameter notify, 64002 once) and `hostProgramLeavesThePreset`; eight single-line mutations of `AudioUnitModel.swift` each made its covering test fail |
| The manual's pictures (Task 6) | taken in the real app with the same scratch hook (removed again): the window captured by the window server with the open menu or popover composited over it (`CGWindowListCreateImageFromArray`), so they show real Liquid Glass. Example presets "Night drone" and "Bright twang" and kits "Drone kit" and "Pulse kit" in temporary folders. 2× (2200 × 1410 for the window), levels cut to 64 per channel; every PNG is under 1.1 MB. Phase 04's six pictures were taken again (header with Preset and MIDI, the new lit buttons) and four are new: the Preset menu open, the name popover, MIDI mode with Vowel listening, the Kit menu open. The marks were checked on a headless Chrome render of the figures |
| The selected pad's outline (final fix wave) | inside the footer's `GlassEffectContainer` the aurora outline, an overlay after `glassEffect`, was drawn under the glass and showed only as a lighter fill. `PadGridView` now draws it as part of what the tile's glass carries; with the same in-app drive and real glass, pad 05 in the retaken `pads.png` shows the aurora outline the manual describes |
| Clean-up after the drive | `io.jp4.brumle` deleted and imported back from the backup, `cmp`-identical; `~/Library/Application Support/Brumle` does not exist; no Brumle process left; `grep -rn "SCRATCH\|ScratchDrive" Sources` finds nothing, and `build/debug` was rebuilt clean |
| Website | `docs/manual.html` and `docs/cs/manual.html` have the same 1719 tags in the same order, with the same ids, classes, marks, anchors and image paths; `docs/index.html` and `docs/cs/index.html` 129 tags each |

## Deviations from the plan

- **Pictures:** the plan asked for renders unless the screen was unlocked. The controller ruled
  for captures of the real app from inside the running debug build instead (real glass), and
  for retaking phase 04's pictures too.
- **No "Defaults" button in the header** (Didgeridoo has one): resetting every controller is in
  the secondary-click menus of the MIDI button and of every control, because the button would
  not fit (1138 of 1080 pt).

## The controller's rulings (from the ledger)

- A: Task 3 adds `kBrumleProperty_SelectedPad = 64003` (read/write UInt32, Global; saved in
  `brumle-pads` as `selectedPad`) with a test; Task 5 only uses it.
- B: Task 5 ran before Task 4; Task 5 implemented the members in both models with the
  signatures of Task 4's protocol additions, and Task 4 then added them to the protocol.
- Task 1 (plan-mandated minor 2): `brumle_changes` becomes release/acquire, in the final fix
  wave. The manual says that a ringing voice follows a CC at its next control tick.
- Task 3: the mirror reads `brumle_changes` after `process` (CCs land inside process; as
  Didgeridoo does).
- Task 3: the mirror compares against `heard_` (the engine's read-back), not `Globals()`, to
  avoid ulp rewrites and needless notifications; cost: 81 floats.
- Task 3: a restored set takes the state's preset name or none.
- Task 5: choices 1 and 3–8 accepted as reported: the present preset is -1 with the preset's
  name; Send to pad carries the preset name; controllers are read every refresh; 64003 is
  written on select and hit; the program index is set before the notify; unknown names are kept
  until edited; `loadProgram` ignores a bad index. Choice 2: the AU itself should clear the
  keyboard's preset name in `NewFactoryPresetSet`, not only the window (final fix wave).
  `lastError` and `lastErrorTime` joined Task 4's protocol additions.
- Task 4: reset-all controllers in context menus, not a Defaults button (header width); MIDI
  mode with a pad shown dims every control and shows "—"; the Program and Preset menus are a
  fixed 150 pt; the Kit button is labelled "Kit"; `LibraryMenuView.swift` is shared by both
  menus; the `KhomusView` hit-test fix in `ModeFooterView` (a phase 04 bug: the khomus art
  swallowed clicks on Curve's row) is accepted.
- Task 4, fix round 1: the on-state of LFO 1, LFO 2, VEL and MIDI is a solid fill under the glass
  (the silver tint read as disabled).
- Task 6: the manual's pictures come from the in-app drive (the real app window rendered inside
  the running app, real glass), phase 04's pictures retaken too, instead of the stand-in preview.

## Carried to the final fix wave (from the ledger)

- `brumle_changes` release/acquire (Task 1); `ControllerMap(capturing:)` drops a CC already seen
  (learn/set race); a hard-coded 34 in a test; a redundant `UInt32` conversion.
- `save`'s catch deletes the temp file after a failed move that followed a successful remove
  (Task 2).
- The AU clears the keyboard's preset name in `NewFactoryPresetSet` (Task 5, choice 2).
- AU vanish-handling writes "" for untouched sets inside actions; one shared folder listing
  instead of 17; deleting the keyboard preset in use leaves the host's present-preset name; a
  detached refresh leaves learning shown; duplicated reporting/padsMoved (Task 5 minors).
- `KnobView`/`ChoiceView` do not cancel a learn on their own disappearance (the models do).

## Not verified

- **A real host (Logic, Live):** loading a user preset and seeing its name as the plug-in's
  preset, choosing a factory preset, saving and reopening a project with controllers, presets
  in use and the selected pad, automation recorded from a CC. Only the unit tests, the window
  tests and auval ran.
- **Real MIDI hardware for learn:** CCs were posted to the engine by hand (`postMIDI`) and
  rendered block by block; no controller was turned, and the MIDI channel filter was not
  exercised with CCs.
- **Real audio output:** no output device rendered while the screen was locked; the sound was
  measured from blocks rendered by hand (carried from phase 04).
- **Sandboxed hosts and the shared folder:** whether a sandboxed host (GarageBand, Logic) lets
  the plug-in read and write `~/Library/Application Support/Brumle/{Presets,Kits}`, and whether
  the app and the plug-in really see each other's files across processes. Two libraries on one
  temporary folder were tested in one process only.
- **The popovers' focus in a host window:** the name popover's keyboard focus, Return and Esc
  inside a plug-in window. In the app's drive, typing reached the field and Esc closed the
  popover; the Save, Replace and Delete buttons were never clicked with the mouse.
- **The menus in a host's menu tracking:** that `lookAtPresets` runs when the menu opens was seen
  in the app only.
