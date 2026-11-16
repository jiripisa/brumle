# Phase 04 — Verification (2026-11-16)

Brumle plays: the standalone app (audio out, MIDI in, Settings, on-screen keyboard and pads) and
the AUv2 instrument with the same panel, both modes, Send to pad and pad editing. The screen of
this Mac stayed locked for the whole phase, so nothing could be captured from a real window and
no audio device rendered (see "Not verified").

The checks below ran on `43038ee` (the last code commit); the phase's final commit changes only
documentation.

| Check | Result |
|---|---|
| `swift test` | `✔ Test run with 160 tests in 26 suites passed after 10.278 seconds.` No `warning:` or `✘` lines |
| `swift test -c release` | `✔ Test run with 160 tests in 26 suites passed after 2.823 seconds.` The 24 regression references hold, so the engine's sound is unchanged |
| `swift test --sanitize=thread` | `✔ Test run with 160 tests in 26 suites passed after 76.512 seconds.` No ThreadSanitizer report |
| `./build.sh debug`, `./build.sh release` | both end with `Build complete: …/build/{debug,release}/Brumle.app`; the app holds `Contents/PlugIns/Brumle.component`, and both carry the artwork in `Resources/Art` |
| `codesign --verify --deep --strict build/release/Brumle.app` | `valid on disk`, `satisfies its Designated Requirement` |
| `nm -gU …/Brumle.component/Contents/MacOS/Brumle` | one symbol: `T _BrumleAUFactory` |
| `auval -v aumu Brml JPis` (run by the controller) | `AU VALIDATION SUCCEEDED.` 81 of 81 parameters PASS; `Cocoa Views Available: 1` (`BrumleAUViewFactory`, PASS); `Component Version: 0.1.0 (0x100)`; manufacturer `Jiri Pisa`, name `Brumle`; Latency and Tail Time PASS. The controller installed the release component into `~/Library/Audio/Plug-Ins/Components/Brumle.component` for this and left it there |
| Review focus 1, host reopens a project | `AudioUnitTests`: "The saved state brings back the keyboard set, the pads and the mode", "A pad's shorter list of values covers the first parameters…" pass in all three runs |
| Review focus 2, automation vs. the panel | `AudioUnitWindowTests`: "A parameter or program the host changes shows in the window at the next refresh", "A drag tells the host where it begins, what it sets and where it ends" pass |
| Review focus 3, pad edits stay in the pad | `AudioUnitWindowTests` "Knobs, programs and resets in pad mode change the pad's set, never the unit's parameters"; `SynthTests` "Writing one pad's set leaves the other pads and the keyboard set as they were"; the app's routing checked by hand (Ruling B) |
| Review focus 4, sample rates and mono | "The latency follows the sample rate: 29 frames below 88.2 kHz, none above", "A mono output gets both sides mixed: (L+R)/2…" pass |
| Review focus 5, no artwork | "The window opens without the component's artwork, at the panel's width" passes |
| A host that disposes the unit before its window | "A window whose unit the host disposed of leaves the unit and its engine alone" passes; with the guard removed, AddressSanitizer reports a heap-use-after-free (Task 6 fix) |
| The app, run by path | `./run.sh` started the clean debug build: `Audio: M4 at 48000 Hz`; window 1100 × 715 with the title bar, not resizable |
| The app, driven inside the running app (Task 5) | a scratch hook, never committed, clicked the real `ContentView` with synthesized events and rendered blocks by hand: a key sounds (1 voice, peak 0.36, last note E2); a pad sounds, is selected and its hit counter rises (peak 0.43); Send to pad copies program, knob and pitch; edits are saved 0.5 s after the last one and on quit; a relaunch restores mode, selected pad, keyboard program and knob, pad note and group; resigning active releases a held pad; MIDI from a scratch sender to the port "Brumle" sounds (peak 0.47, last note D3); Settings opens and Install without a bundled component does nothing harmful |
| The plug-in window in a scratch host (Task 6) | loads the built component, registers it in-process, plays note 50, gets `BrumleAUViewFactory` from `kAudioUnitProperty_CocoaUI`, opens an `NSHostingView` of 1100 × 705 in keyboard and in pad mode, with the artwork from the component's bundle |
| The manual's pictures | rendered from the real `BrumleUI` panel by the scratch preview program, with a stand-in for glass (a tinted translucent fill), the default keyboard set and the default kit; 2200 px wide (2×); levels reduced to 5 bits per channel to keep each file under ~1.6 MB |
| Website | `docs/manual.html` and `docs/cs/manual.html` have the same 1159 tags in the same order, and the same ids, anchors and marks; `docs/index.html` and `docs/cs/index.html` 123 tags each |

## Deviations from the plan and the spec

- **Window height:** 1100 × 705 pt (715 with the title bar), not ≈ 690 (decision 11). The panel
  above the footer is 473 pt and the footer 222 pt.
- **Screenshots:** the plan asked for `screencapture` of the real window. The screen was locked,
  so the manual's pictures are renders (see "Not verified").
- **The controller's rulings** (from the ledger):
  - A: no `showsKeyboard`; both front ends show the keyboard strip in keyboard mode.
  - B: the pad-vs-keyboard routing is pinned by Core (`padSetsApart`) and by
    `AudioUnitWindowTests.padEditsStayInPad`; the app's routing is a thin call into `Synth`,
    checked by hand.
  - C: the "click sounds" check falls to the controller when the implementer cannot hear.
  - D: the controller, not a subagent, installs the component for auval.
  - E: screenshots by `screencapture -l`, else renders of the real panel.
  - `KeyStrip` keeps Didgeridoo's 40…127 velocity mapping.
  - `Synth.state` rounds plain values to 6 significant digits.
  - The ClassInfo notice (decision 3) goes through a write-only property
    `kBrumleProperty_StateChanged = 64002` set by the view.
  - The keyboard's program index is saved as `keyboardProgram` in `brumle-pads`, restored without
    reloading values.
  - Curve and LFO Start are full-width segmented rows.
  - The window stays ≤ ~705 pt plus the title bar; the footer ≤ 230 pt.
  - The header has a trailing slot (the app's gear; phase 05's Preset and MIDI).
  - Custom glass segments instead of `Picker(.segmented)`; the LFO rate knobs dim in amount
    modes; `static var width`.
  - `InstrumentPanel(model:) { footer } trailing: { … }`: the trailing slot comes after the
    footer.
  - Dragging across keys plays only the first key; no glissando.
  - A pad with no built-in program is named "Custom".
  - The plug-in window re-checks property 64001 on each refresh and lets go of a unit the host
    disposed of.
  - Property 64002 is sent once after a drag ends (0.5 s debounce) and on window close.
  - The manual's pictures are renders of the real panel, to be replaced by real window shots.

## Not verified

- **Real Liquid Glass and real window screenshots.** The screen was locked, so `screencapture`
  and window capture failed. The manual's pictures are renders with a stand-in for glass; the
  LFO 1 and VEL pictures carry a few amounts set for the example. Retake them on an unlocked
  session (the release does anyway).
- **Sound through a real device.** No output device rendered while the screen was locked (a
  probe got 0 render calls on the speakers and on two other devices); the sound was measured
  from blocks rendered by hand.
- **The plug-in in Logic or Live:** opening it, automation, saving and reopening a project, and
  whether `onDisappear` fires when a host hides the window rather than closing it (held notes
  and the pending host notice depend on it). Only auval and the scratch host ran.
- **Pads are released on mouse-up only:** dragging off a pad keeps it held until the button is
  let go (keys release on drag-out). The manual says so; whether it feels right is open.
- **The host-preview rendering** (ImageRenderer in the scratch host) showed light panels, a
  faint Program menu and no outline on the selected pad. This may be ImageRenderer's lack of
  glass; check it on the real plug-in window.
- **The wheels are unsmoothed:** a real controller may zipper (carried from phase 02).
- **The "Custom" pad name** for a pad whose program is not a built-in one: the word is the
  implementer's choice, and no path in the app reaches it yet.
