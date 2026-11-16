# Phase 08 — Version 1.0.0 — Verification (2026-11-16)

The author asked for version 1.0, a release and the catalog ("nastav verzi na 1.0, releasni to
a aktualizuj katalog"). What changed in the app since 0.1.0 is the icon (phase 07); the website
got its new look in the same phase. Major version because the author said so.

| Check | Result |
|---|---|
| `swift test` on the release branch | 275 tests in 33 suites pass |
| `./build.sh dist` | both notarizations `status: Accepted`; "Done! Signed and notarized DMG" |
| `spctl -a -vv build/release/Brumle.app` | accepted, `source=Notarized Developer ID` |
| Build version | minos 26.0, sdk 26.0 |
| `docs/appcast.xml` | 1.0.0, URL `…/v1.0.0/Brumle-1.0.0.dmg`, length 14 964 769 = the DMG's size, a new EdDSA signature |
| The icon of the notarized app, rendered through `NSWorkspace` | fills the tile, no plate |
| Website version strings | every 0.1.0 on the four pages is 1.0.0, download links point at v1.0.0 |

The window did not change, so the website keeps its screenshot.

## Not verified

- The update from 0.1.0 to 1.0.0 through Sparkle on a Mac that has 0.1.0 installed (the author is
  asked to confirm).
