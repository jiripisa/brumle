# Redo two Brumle assets: knob.png and ornament.png

Same project and rules as `PROMPT.md` in this directory (read it; the approved mockups are in
`reference/`). The first versions of these two files are in `v1/` and are too weak: the knob
is a flat pale disc, the ornament a thin plain outline. Replace `knob.png` and `ornament.png`
in the current directory. Do not touch the other files.

1. `knob.png` — 512 × 512, real transparent background. Match the knob caps in
   `reference/concept-2-keyboard.png`: a substantial, slightly domed **lathe-turned silver
   cap** (fine concentric machining rings), seen from straight above, lit softly from the top
   left so it reads as polished metal with depth: a bright specular area upper-left, darker
   steel lower-right, a thin darker bevel and a soft round shadow under it. Mid-to-dark silver
   overall (it sits on a midnight-blue panel and a light pointer line is drawn over it, so it
   must not be near-white). Cap diameter about 80 % of the canvas, centred. The image does NOT
   rotate in the app (only a pointer drawn in code turns), so directional light is fine — but
   **no pointer, notch, tick, dot, indicator or marking of any kind**, no text.
2. `ornament.png` — 2400 × 64, real transparent background. Match the band at the bottom of
   `reference/concept-2-keyboard.png` and the strips in `reference/concept-2-pads.png`: an
   **engraved silver strip** — two fine parallel silver rails along the top and bottom edges
   with a continuous chain of small filled/engraved diamonds between them (alternating a
   solid diamond and an outlined diamond with a dot), metallic shading, dark engraving lines.
   It must tile seamlessly left-to-right (right edge continues the left). No large central
   medallion (it is tiled). No text.

Normalize to the exact sizes with `sips`, verify `sips -g hasAlpha` says yes for both, and
verify the ornament tiles (compare its first and last columns). Append a short "Round 2"
section to `assets.md`. Write nothing outside this directory except your image tool's own
staging. Do not ask questions.
