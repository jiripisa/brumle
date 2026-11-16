# Artwork assets for "Brumle" — concept 2 "Polar Khomus"

Use your image generation tool to create the artwork below, then save each as a PNG in the
current working directory with the exact name given. The approved mockups are in
`reference/concept-2-keyboard.png` and `reference/concept-2-pads.png`: match their look.

Brumle is a synthesized jaw harp for macOS 26 (app and Audio Unit). The panel is built in
SwiftUI: every label, value, knob pointer/arc, pad, key, menu and button is drawn live in code
with Liquid Glass. You make ONLY the decorative raster art the code places behind or under them.

**Absolute rule: no text, letters, digits, labels, UI controls, knobs, pads, keys, buttons,
arcs or highlights baked into any image** (the wordmark "Brumle" is drawn as live text too).

Palette: midnight `#111C29`, slate `#24374A`, icy silver `#CBDCE4`, bone `#E9DEC4`,
aurora cyan `#67D6D3`. Mood: cool, nocturnal Sakha khomus — brushed/engraved silver, weathered
bone, dark leather, soft fur-like detail, northern geometric diamond ornament (craft-inspired
abstraction, not a claim of authentic traditional patterns).

## Deliverables

1. `background.png` — **2200 × 1375** (16:10), opaque. The whole window background: dark
   midnight/slate leather with a subtle vignette, faint fur texture at the edges, perhaps a
   very faint engraved diamond pattern. It must be calm and dark everywhere so that glass
   panels and light text on top stay readable; no strong focal object. Lower-right corner may
   be slightly richer (the pad view puts the khomus emblem there).
2. `khomus.png` — **1200 × 1200**, transparent background (real alpha). A Sakha khomus (jaw
   harp) in brushed and engraved silver with a thin steel reed, three-quarter view, as in the
   mockups' lower-right artwork. Soft contact shadow allowed; no background.
3. `logo.png` — **512 × 512**, transparent background. The emblem only: a small stylised
   silver khomus frame inside an engraved diamond/rhombus, usable at 40 pt beside the live
   wordmark. No text.
4. `knob.png` — **512 × 512**, transparent background. A round knob cap seen straight from
   above: brushed silver with a fine bone/silver bevel ring, soft drop shadow inside the
   canvas. **Rotationally symmetric, with NO pointer, notch, tick or marking**, centred, cap
   diameter about 80% of the canvas (code draws the pointer and value arc around it).
5. `ornament.png` — **2400 × 64**, transparent background. A horizontal engraved silver
   strip of northern diamond ornament that tiles seamlessly left-to-right (the right edge must
   continue the left edge). Used as a thin band under the header and above the keyboard/pads.

## Process

- Generate, then normalize each file to the exact pixel size with macOS `sips`
  (`sips -z H W` or crop with `sips -c`), keeping transparency where required.
- Check alpha: `sips -g hasAlpha <file>` must say yes for 2–5. If the generator gave you an
  opaque image, remove the background (e.g. with a Python script using only the standard
  library is NOT required — prefer regenerating with a transparent background).
- Write `assets.md`: one line per file (size, alpha, what it is), plus any choices you made.

Your image tool's automatic staging under `$CODEX_HOME/generated_images/` is fine: copy the
final PNGs from there into the current directory. Apart from that, write nothing outside the
current working directory. Do not stop to ask questions: make sensible choices and note them
in `assets.md`.
