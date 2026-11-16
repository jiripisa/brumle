# Brumle — Roadmap

Phases, newest first. One phase = one folder in `phases/`, one branch, one
`--no-ff` merge.

| Phase | Goal | Status |
|---|---|---|
| 06-v0.1.0-release | The first release, v0.1.0, with the project skill `release` | next |
| 05-presets-kits-midi-learn | User presets, kits (all 16 pads) as files shared by the app and the plug-in, MIDI controllers and learn, the AU saving controllers, presets in use and the selected pad; manual EN + CS — 2026-11-16 | ✅ |
| 04-app-and-audiounit | The app and the AUv2 with the shared panel in the "Polar Khomus" look, both modes, mute groups, Send to pad, pad editing, LFO and VEL amounts on the knobs, auval, manual EN + CS — 2026-11-16 | ✅ |
| 03-panel-design | Codex artwork of concept 2 "Polar Khomus": background, khomus, logo, knob cap, ornament — 2026-11-16 | ✅ |
| 02-engine | Sound engine: `BrumleDSP` (voice pool, 17 knob sets, keyboard and pad modes, mute groups, LFOs, VEL amounts, 2× oversampling) and the `BrumleCore` wrapper; macOS 26 — 2026-11-16 | ✅ |
| 01-skeleton | Empty app skeleton: SwiftPM, build/run scripts, signing + notarization pipeline, website — created 2026-11-15 | ✅ |
