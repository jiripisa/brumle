# Brumle — State

- 2026-11-16 — phase 05 (presets, kits, MIDI learn) done: user presets loaded into the keyboard
  or a pad, kits of all sixteen pads, a MIDI controller with learn on every knob and switch of
  the keyboard's sound; the plug-in saves controllers, presets in use and the selected pad.
  Manual in EN and CS with pictures of the real app. Not yet seen: a real host, MIDI hardware,
  sound through a device, sandboxed hosts and the shared folder (VERIFICATION.md).
  Next: phase 06-v0.1.0-release.
- 2026-11-16 — phase 04 (app and Audio Unit) done: Brumle plays, as the app and as the AUv2
  with the same panel (keyboard and pad modes, mute groups, Send to pad, pad editing, LFO and
  VEL amounts); auval passes; manual in EN and CS. Not yet seen on an unlocked screen: real
  glass, real screenshots, sound through a device, a real host (VERIFICATION.md).
  Next: phase 05-presets-kits-midi-learn.
- 2026-11-16 — phase 02 (engine) done and merged: the C++ engine behind a C API and the
  `Synth` wrapper, proven against the prototype; listening renders approved by the author.
  Not playable yet.
- 2026-11-16 — phase 03 (panel design) done: Codex artwork of concept 2 in `Resources/Art/`.
- 2026-11-15 — skeleton created (phase 01): empty window, `BrumleCore` with one
  test, `build.sh` / `run.sh`, Developer ID + notarization pipeline,
  Sparkle auto-update, website on GitHub Pages.
