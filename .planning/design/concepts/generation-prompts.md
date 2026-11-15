# Brumle — image-generation prompt set

Built-in image generation was used for every mockup. Each keyboard view was a fresh generation with the shared specification, concept direction and keyboard specification below. Each final pad view was an edit of its corresponding keyboard image, preserving the header and parameter panels while replacing the lower area. A first full-width pad experiment for concept 1 was superseded by the split layout.

## Shared keyboard generation specification

```text
Use case: ui-mockup. Generate one polished straight-on full-window UI design mockup for Brumle, a synthesized jaw harp native macOS 26 instrument and Audio Unit plugin. Exact image aspect 16:10, landscape, preferably 1600 x 1000 pixels. The app fills the canvas, no desktop, no perspective, no laptop, no mockup caption, no external margins. This is a usable dense musical instrument, with macOS Liquid Glass translucent panels and restrained reflections, sharp highly legible typography, clear knob pointers and value readouts. Material artwork is beautiful but behind calm control surfaces. Jaw harp motif must be an actual horseshoe/lyre forged frame with a thin straight steel reed inside, not a string harp.
LAYOUT: Header y=0-115, five titled parameter panels y=130-565, mode area y=590-950, thin ornament/footer to 1000. Header wordmark Brumle and small jaw harp symbol left, two menus labeled Program with value Khomus and Preset with value Ember Pulse, segmented Keyboard | Pads control, three buttons LFO 1, LFO 2, VEL, and MIDI learn button labeled MIDI. All fit in one or two tidy header rows.
ALL FIVE PARAMETER SECTIONS AND ALL FOLLOWING LABELS MUST BE VISIBLE VERBATIM. Every rotary has its label above and a short numeric/text value below. No other parameter labels. Use compact organized grids, every item once, no omitted controls.
Reed (2 columns x 3 rows): Ring 72%, Edge 38%, Offset 0.12, Body 64%, Buzz 22%, Clang 31%.
Stroke (2 columns x 3 rows): Vel Sens 80%; Stroke segmented Out / In / Alt with Alt selected; Damp 28%; Key Up segmented Ring / Damp with Ring selected; Vary 12%.
Mouth (3 columns x 3 rows, widest panel): Vowel 0.42, Sweep +35%, Sweep Time 180 ms, Curve four-way selector 1 / 2 / 3 / 4 with 2 selected, Reso 68%, Throat 45%, Throat Tune 220 Hz, Open 70%, Close 18%.
Breath (2 columns x 2 rows): Breath 20%, Puff 35%, Puff Time 90 ms, Air 16%.
Master (3 columns x 3 rows): Volume -6 dB, Pan C, Tune 0 ct, Octave -1, Bend>Vowel 40%, LFO 1 rate 1/8, LFO 1 shape Sine, LFO 2 rate 1/4, LFO 2 shape Tri. Rate is a knob; shape is a small menu with readable value. About thirty knobs, modest 45px caps, strong contrast. Make labels large enough to read at normal image size. Never replace the full parameter list with artwork.

```

## Concept directions

### Concept 1

```text
CONCEPT 1, HEARTH & IRON: warm honeyed walnut, hand-forged charcoal iron, aged brass accents, narrow Central European embroidered russet/ivory folk zigzag and floral band. Palette walnut #563A29, charcoal #242522, ivory #F3E8D5, brass #C79952, russet #A54D3C. App feels warm, contemporary and crafted. Dark softly frosted glass parameter cards float over subtle carved walnut; pale ivory highly readable labels; satin iron knob caps with thin brass position arcs, no oversized rivets. Brumle wordmark is a distinctive humanist serif; UI typography modern SF Pro-style sans. A photoreal forged jaw harp lies discreetly across an exposed wood strip. Thin folk embroidery only around the edges, quiet under controls. Glass has restrained specular rim and believable backdrop blur. Artwork 45%, glass 55%.
```

### Concept 2

```text
CONCEPT 2, POLAR KHOMUS: Siberian Sakha khomus inspired, midnight blue-black #111C29, slate #24374A, icy silver #CBDCE4, warm bone #E9DEC4, restrained aurora cyan #67D6D3. Dark brushed metal and worn bone with a narrow northern geometric carved diamond band, no generic fantasy or runes. Dark blue translucent Liquid Glass cards, extremely legible silver/ivory text, fine cyan arcs on satin silver knobs. Sculptural silver jaw harp silhouette over softly lit charcoal leather/bone artwork. Wordmark angular refined serif, UI neutral SF Pro-style. This is cool, precise, nocturnal and materially distinct from wood concept. Artwork 35%, glass 65%.
```

### Concept 3

```text
CONCEPT 3, MORSING / INDIGO: Indian morsing-inspired hammered brass #C79542, deep indigo #202343, aubergine #39243E, saffron #E4A449, cream #F7EAD0. Elegant jewel-toned woven silk and a very narrow South Indian kolam-inspired geometric line ornament, culturally respectful craft abstraction, no religious symbols. Translucent plum/indigo glass parameter panels with high-contrast cream text, contemporary small brass knobs with luminous amber position marks. A real brass horseshoe morsing frame and slender reed integrated in an exposed decorative strip. Warm luminous brass and deep colours, editorial serif Brumle wordmark and SF Pro-style UI. Rich but uncluttered, not a vintage rack plugin. Artwork 50%, glass 50%.
```

### Concept 4

```text
CONCEPT 4, REED / GLASS: restrained bright modern mostly-glass instrument. Pale mineral background #E9EEEC, frosted white #F8FBFA, graphite text #25312F, desaturated jade accent #4F8579, light silver #BCC9C5. Large ghosted jaw harp silhouette under milky translucent glass; single thin sage woven geometric ornament band only at bottom. No wood panel, no jewel tones, no decorative borders elsewhere. Clear floating Liquid Glass header controls and softly frosted glass parameter groups with fine grey boundaries; transparent polished knob caps, graphite pointers, jade arcs, dark readable labels. Brumle wordmark clean contemporary rounded sans with tiny minimalist jaw harp emblem. Typography SF Pro-style. Modern Mac app with ample optical breathing room despite full control inventory. Artwork 10%, glass 90%.
```

## Keyboard mode

```text
MODE: Keyboard selected in header. Lower area includes title Keyboard, compact pitch C2 and a button Send to pad aligned right. Show an elegant two-to-three octave on-screen piano keyboard strip, correct familiar black/white key arrangement, keys labeled subtly at C2, C3, C4. Use generous horizontal space for keyboard and a beautiful shallow jaw-harp material/artwork strip behind or above it, within lower area's allotted space. No pad grid.
```

## Pad mode edit specification

```text
Edit the corresponding keyboard mockup into matching Pads mode. Preserve all top parameter panels, every control, header, typography, palette, materials and ornament. Select Pads in the header; remove the keyboard and Send to pad button. Preserve landscape 16:10.

MODE: Pads selected in header. Lower area is a strict 4 columns x 4 rows grid of EXACTLY 16 broad MPC pads, all sixteen fully visible, no piano. Compact title Pads and status Selected: 01 · Ember. Each pad has four readable fields number, sound name, pitch, mute group, with this exact content in reading order: 01 Ember C2 G1; 02 Birch D2 G1; 03 Copper E2 G2; 04 Hollow F2 G2; 05 Pulse G2 G1; 06 Reed A2 G1; 07 Frost B2 G2; 08 Drone C3 G3; 09 Spark D3 G2; 10 Wood E3 G2; 11 Air F3 G3; 12 Bell G3 G3; 13 Earth A3 G4; 14 Echo B3 G4; 15 Night C4 G4; 16 Dawn D4 G4. Pad 01 visibly selected with accent outline and lit surface. All other pads calmer. Upper knobs show selected pad's sound. Grid uses 4 full-width columns and 4 compact equal rows, no extra rows or pads.

PAD COMPOSITION: The lower area is split: left 62% is the pad bank, right 38% shows a beautiful jaw harp on the concept's material plus selected sound information. Place the 4x4 bank in the left region. Pads must be rounded rectangular MPC trigger tiles, with number and sound name on first line and pitch plus mute group on second line; do NOT use single-line table/list rows. Every pad is a distinct filled touch target. Use generous separation, legible 16px labels, identical sizes, four rows exactly. Keep top parameter panels exactly as reference.

The split layout overrides the earlier full-width grid instruction. Retain the concept's jaw-harp illustration and material vignette on the right. All sixteen pad names and fields must be exact and legible. Concept 1: warm smoked brown glass with brass/amber selection. Concept 2: dark blue glass with cyan selection. Concept 3: plum glass with amber selection. Concept 4: milky glass with graphite type, jade selected pad with white type and a strong border.
```

