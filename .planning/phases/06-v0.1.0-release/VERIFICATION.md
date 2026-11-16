# Phase 06 — Version 0.1.0 — Verification (2026-11-16)

The first release: the engine (phase 02), the artwork (03), the app and the Audio Unit (04),
presets, kits and MIDI learn (05). The author asked for it to be released ("Ok, releasni to",
answering a question that named the push to GitHub). The repository was already public.

| Check | Result |
|---|---|
| Version | 0.1.0, the first release — the version the skeleton carries and the website links point at |
| `swift test` on the release branch | 275 tests in 33 suites pass |
| `./build.sh dist` | both notarizations `status: Accepted`; ends with "Done! Signed and notarized DMG" |
| `spctl -a -vv build/release/Brumle.app` | accepted, `source=Notarized Developer ID`, Developer ID Application: Jiri Pisa (88X62ZUGT7) |
| The app's build version (`vtool -show-build`) | minos 26.0, sdk 26.0 — the system draws it as a macOS 26 app |
| `docs/appcast.xml` (new) | 0.1.0, minimum system 26.0, URL `…/releases/download/v0.1.0/Brumle-0.1.0.dmg`, length 12 724 403 = the DMG's size, an EdDSA signature |
| Release notes | the CHANGELOG's 0.1.0 section; one line that only described a change between unreleased builds (the lit LFO/VEL/MIDI buttons) was removed and the appcast written again from the same DMG |
| The release app, opened by path | its window shows the panel with real Liquid Glass, the artwork, both menus and the keyboard; quit afterwards |
| auval on the same code (main 9e5b677) | AU VALIDATION SUCCEEDED, 81 parameters, Cocoa Views Available: 1 |

The website's screenshot stays the phase-05 picture of the same build state: the manual's
numbered frames are placed on its geometry (the release capture adds a title bar).

## Not verified

- The plug-in in Logic Pro or Ableton Live, and in a sandboxed host (GarageBand).
- Sound through an audio device and MIDI learn with a hardware controller.
- The update path: there is no older release to update from.
