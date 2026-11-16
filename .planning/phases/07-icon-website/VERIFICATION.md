# Phase 07 — Verification (2026-11-16)

| Check | Result |
|---|---|
| The icon macOS shows for `build/release/Brumle.app`, rendered through `NSWorkspace` | the artwork fills the tile, no light plate or frame (`icon-as-macos-shows-it.png`); transparent outside the tile, opaque inside |
| `Resources/AppIcon.png` | 1024 × 1024, alpha mask identical to Didgeridoo's accepted icon (opaque bounds 100…924); readable at 16–256 px |
| Website in headless Chrome (Codex's renders, looked at by the controller): EN overview at 1440 and 400 px, CS overview at 1440 and 400 px, manual EN at 1440 and 400 px, CS manual at 1440 px | dark midnight ground, serif headings, hero khomus illustration beside the heading (below it on a narrow screen), ornament dividers, the real app window; no horizontal overflow, no failed images |
| EN and CS overview | the same structure, tag for tag; text, links and version strings unchanged |
| Manual | HTML unchanged; its 48 marks and 11 figures keep their geometry |
| Image sizes | hero JPEG 422 KB, ornament PNG 23 KB, site icon 81 KB |

## Not verified

- The icon on macOS 14/15 is irrelevant (the app needs macOS 26); in the Dock and Finder it was
  seen only through `NSWorkspace`'s rendering.
- The website in Safari and on a real phone.
