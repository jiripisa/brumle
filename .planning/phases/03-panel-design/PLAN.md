# Phase 03 — Panel design: the artwork of concept 2 "Polar Khomus"

**Goal:** the raster artwork the panel of phase 04 is built on, made by Codex as separate
assets, as spec §10 says. Design and assets only: no code.

**Spec:** `.planning/specs/2026-11-15-engine-design.md` §10. The mockups are
`.planning/design/concepts/concept-2-keyboard.png` and `concept-2-pads.png`.

## What is made

Into `Resources/Art/`, as Didgeridoo keeps its art:

| File | Size | Alpha | Use in the panel |
|---|---|---|---|
| `background.png` | 2200 × 1375 (16:10) | no | the whole window behind the glass groups: dark midnight leather, faint fur at the edges, a faint diamond pattern |
| `khomus.png` | 1200 × 1200 | yes | the silver khomus over the keyboard strip (keyboard mode) and at the lower right (pad mode) |
| `logo.png` | 512 × 512 | yes | the emblem beside the live "Brumle" wordmark in the header |
| `knob.png` | 512 × 512 | yes | every knob's cap; the pointer and the arcs are drawn in code over it, the cap itself does not turn |
| `ornament.png` | 2400 × 64 | yes | the engraved diamond strip, tiled horizontally under the header and around the mode area |

The rules Codex was given (`.planning/design/assets/PROMPT.md`, `PROMPT2.md`):
- The palette is §10's: midnight `#111C29`, slate `#24374A`, icy silver `#CBDCE4`, bone `#E9DEC4`
  and aurora cyan `#67D6D3`.
- No text, labels, controls, arcs or highlights are baked into any image. The wordmark,
  every label, every value, the knob pointers and the selection states are drawn live.
- The knob cap carries no pointer or marking.
- The ornament tiles seamlessly.

## Acceptance

- Every file has its exact size, and alpha where the table says so (`sips`).
- The ornament's first and last columns continue each other.
- A composite of the assets on the mockup's layout reads like the mockup: a dark, calm
  background; silver that stands out without glare. The controller judges this by eye; the
  author approves it when they are back. Anything rejected is regenerated before phase 04
  ships, since phase 04 only needs the file names and sizes.
- `./build.sh release` copies `Resources/Art` into the app: that is phase 04's work in
  `build.sh`, together with the component.
