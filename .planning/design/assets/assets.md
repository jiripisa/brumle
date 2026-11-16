# Brumle — Polar Khomus artwork

- `background.png` — 2200 × 1375; alpha: no, fully opaque; midnight leather with a subtle vignette, faint edge fibers, and barely visible diamond embossing.
- `khomus.png` — 1200 × 1200; alpha: yes, real transparent background and openings; weathered engraved silver khomus with steel reed, loop left and hooked tip right.
- `logo.png` — 512 × 512; alpha: yes; simplified silver khomus inside an engraved diamond, with transparent padding and openings.
- `knob.png` — 512 × 512; alpha: yes; centered rotationally symmetric brushed silver cap with a fine bone/silver bevel, approximately 80% canvas diameter, no pointer or markings.
- `ornament.png` — 2400 × 64; alpha: yes; engraved silver diamond band, 30 identical 80 × 64 repeat units, seamless horizontally.

## Choices and verification

Artwork was generated with the built-in image generation tool after viewing both approved reference mockups. All final PNGs are in this directory. No text, wordmark, interface panels, keys, pads, buttons, value arcs, indicators, or glow overlays are included. The knob file contains only the specifically requested blank decorative cap. Metal has diffuse material shading and bevels.

The background stays dark across the full canvas; the lower right has slightly richer leather grain. Bone is confined to the cap's fine bevel. Cyan is reserved for live interface rendering. Ornament is craft-inspired geometric abstraction without an authenticity claim.

The khomus retains its proportions, with transparent square-canvas padding. The logo has extra transparent breathing room and was visually checked at 40 pixels. The ornament uses a single generated motif repeated exactly; transparent gaps between diamonds continue uniformly across the file boundary. No endcaps are included.

All files were normalized with macOS `sips`. Native macOS CoreGraphics/ImageIO handled transparent padding, repeating the generated ornament tile, and averaging the generated cap by radius to remove angular lighting variation. The cap retains the generated material's concentric variation and has exact quarter-turn pixel symmetry. The sips JavaScript exporter did not produce output, so native APIs completed those mechanical steps.

Verification: `sips -g pixelWidth -g pixelHeight -g hasAlpha` confirmed the listed dimensions and alpha flags. Pixel inspection confirmed a fully opaque background and actual zero-alpha pixels in all four transparent assets. Exact 80-pixel periodicity and transparent left/right joins were checked for the ornament. The assets were visually inspected composited on the generated background, including small-size logo and cap previews.

## Generation prompts

The following are the prompts supplied to the built-in image tool; the cap also received the refinement below. Final mechanical normalization is described above.

### background

Create one decorative raster artwork asset, no interface. Landscape 16:10, ideally 2200x1375, fully opaque. Full-bleed midnight #111C29 and dark slate #24374A fine-grained weathered leather, cool nocturnal northern atmosphere matching the viewed Brumle Polar Khomus mockups. Very subtle vignette, faint soft dark fur-like fibers only along outer edges, a trace of almost invisible embossed geometric diamonds. Calm dark low-contrast texture across the entire center and all areas intended behind readable light text and glass UI. Lower right slightly richer grain, still very dark. No focal object. NO text letters digits logos wordmark UI panels controls knobs caps pads keys buttons arcs indicators glowing marks or bright highlights. No silver band or instrument in this background. Restrained realistic tactile material, not a scene.

### khomus

Generate a single isolated Sakha khomus jaw harp decorative raster cutout, 1200x1200 square with REAL transparent alpha background. Match the weathered engraved silver instrument from the viewed Polar Khomus mockups: broad rounded teardrop loop on the LEFT tapering into two long narrow nearly parallel steel arms to the RIGHT, delicate thin straight central steel reed ending with a tiny upturned hooked tip at the far right. Three-quarter view with subtle depth, horizontal with slight diagonal, whole instrument visible within generous transparent margins. Brushed icy silver #CBDCE4 with worn dark recesses and restrained northern geometric diamond engravings around broad loop, craft-inspired abstraction. Elegant handmade aged metal, clean physically believable coherent single instrument. Around 85% canvas width. No bone support, fur or leather backing, no floor, no background whatsoever; all holes truly transparent. Very subtle contact shadow allowed. NO text letters digits labels wordmarks UI controls knobs pads keys buttons arcs indicators glow or added highlight overlays. Soft even diffuse material shading only.

### logo

Generate a single decorative emblem only, square 512x512 with REAL transparent alpha background. A small stylized icy-silver khomus frame inside an engraved silver diamond/rhombus outline, matching weathered silver from the viewed Brumle Polar Khomus mockups. Strong simple legible silhouette usable at 40pt: bold diamond outline with very restrained shallow geometric engraving, central khomus frame recognizable as rounded loop tapering to two slender arms with thin central reed, oriented diagonally upward right. Balanced centered design, ~80% canvas extent, enough space inside diamond. Brushed silver #CBDCE4, discreet dark patina; openings and surroundings completely transparent, no backing plate. Photoreal crafted metal emblem with simplified detail. NO text letters digits labels wordmark interface controls knobs pads keys buttons arcs UI highlights glow or aurora effects.

### knob

Generate one plain circular decorative metal knob CAP only, 512x512 square, REAL transparent alpha background. Strict orthographic straight overhead view, precisely centered circle, cap diameter 80% of canvas, all edges and soft centered ambient shadow contained in canvas. MUST BE ROTATIONALLY SYMMETRIC: uniform concentric circular brushed silver machining, isotropic ring-shaped material gradients; no directional light wedge, no anisotropic streak, no off-center reflection. Icy silver #CBDCE4 face, thin fine bone #E9DEC4 and silver bevel ring. Subtle aged refined metal matching Polar Khomus references. Absolutely NO pointer notch tick groove that indicates angle, markings numbers letters symbols radial line screw hole logo highlight streak value arc colored cyan ring or UI controls. Complete continuous circular bevel only, no broken arcs. No pedestal or panel or backdrop. Soft rotationally uniform diffuse shading, not bright highlights. This blank cap is the sole requested component; do not draw a complete interface knob with indicator.

### ornament

Generate ONE repeat-unit of a horizontal northern diamond ornamental strip on REAL transparent alpha background, square image 1024x1024. A single centered wide hollow diamond/rhombus made of engraved brushed icy silver #CBDCE4, matching the thin silver diamond ornament at the bottom of the viewed Brumle Polar Khomus mockups. Simple double-beveled slender silver outline with subtly dark patina recessed engraving, craft-inspired abstract geometry, no claim of authentic tradition. Rhombus spans about 76% width and 60% height, centered, entire shape inside transparent padding; all outermost edges completely transparent. Interior hollow and transparent. Strict front-facing flat ornamental geometry, subtle realistic diffuse metal shading, no bright highlights. This unit will be repeated horizontally to form a seamless 2400x64 decorative band. Single diamond only, no long rails or endcaps or background plate. NO text letters digits labels wordmark controls knobs pads keys buttons arcs symbols within diamond glow or UI.

### Cap refinement

Refine this blank metal cap into a strictly rotationally symmetric asset. Keep actual transparent alpha background and no text or indicators. Square canvas. Exact circle centered in canvas, overall silver cap diameter exactly 80% canvas. Perfect straight overhead orthographic view. Remove asymmetric lighting and directional reflections: equal appearance around every angle, concentric isotropic circular brushed silver texture and uniform continuous thin bone/silver bevel. The whole image must look identical when rotated; no brighter top, darker bottom, wedge lighting, horizontal brushing, localized rim highlight, notch, pointer, marking, tick, broken arc, or angular detail. Soft centered circular ambient contact shadow only with equal weight all directions. Retain realistic refined silver and pale bone materials in diffuse light.


## Round 2

- `knob.png` — 512 × 512; real alpha; substantial, slightly domed lathe-turned silver cap, approximately 80% canvas diameter, fine concentric machining, bright upper-left reflection, darker steel lower-right, narrow dark bevel and subtle contact shadow. No pointer or markings. Directional lighting intentionally replaces Round 1's rotationally symmetric lighting.
- `ornament.png` — 2400 × 64; real alpha; two continuous silver rails surrounding alternating filled engraved diamonds and outlined diamonds with central dots. Eight 300 × 64 repeats, 32 diamonds total, no central medallion.

Generated with the built-in image tool using both approved mockups as style references (keyboard reference for the cap). Prompt direction: blank machined silver cap with depth and medium-to-dark directional metal shading; seamless engraved silver rails with alternating solid and dotted-outline diamonds. Normalized with `sips`; native Swift/CoreGraphics repeated the generated ornament and matched its connecting rails/thread across an eight-pixel seam zone. No rotational averaging was applied to the cap.

Verification: `sips` confirms exact dimensions and `hasAlpha: yes` for both. Pixel checks found 119,540 fully transparent pixels in the cap and 86,576 in the ornament. First/last ornament columns have zero RGBA differences; the 300-pixel repeat is exact. Both were visually checked over midnight blue. Other artwork, references, and v1 files remain unchanged.
