# Design concepts for "Brumle" — a synthesized jaw harp instrument for macOS

Use your image generation tool to create UI mockups, then save them as PNG files in the
current working directory with the exact names given below.

## The product

Brumle ("brumle" is Czech for jaw harp / Jew's harp) is a software instrument: a native
macOS 26 app and an Audio Unit plug-in that shows the same window inside music hosts (Ableton
Live, Logic Pro). It synthesizes a jaw harp and is used mainly for rhythm. The window is a
landscape panel of about 1100 × 700 points.

## What the window must show (every mockup must contain these, legibly)

**Header bar:**
- the "Brumle" logo or wordmark;
- a Program menu (e.g. "Khomus") and a Preset menu;
- a mode switch with two segments, **Keyboard | Pads**;
- three modulation buttons, **LFO 1**, **LFO 2** and **VEL**;
- a **MIDI** learn button.

**Knob sections, each titled:**
- **Reed:** Ring, Edge, Offset, Body, Buzz, Clang.
- **Stroke:** Vel Sens, Stroke (a 3-way switch Out/In/Alt), Damp, Key Up (switch Ring/Damp),
  Vary.
- **Mouth:** Vowel, Sweep, Sweep Time, Curve (a 4-way selector), Reso, Throat, Throat Tune,
  Open, Close.
- **Breath:** Breath, Puff, Puff Time, Air.
- **Master:** Volume, Pan, Tune, Octave, Bend>Vowel, and LFO 1/LFO 2 rate and shape.

About 30 knobs in all: they must stay readable, each with its name and value.

**Mode-specific area, below the knobs:**
- *Keyboard mode:* a two-to-three-octave on-screen piano keyboard strip and a **Send to
  pad** button.
- *Pad mode:* a **4 × 4 grid of 16 pads**, MPC-style. Each pad shows its number, the sound's
  name, its pitch (e.g. "C2") and its mute group (e.g. "G1"). One pad is selected, and the
  knobs above show that pad's sound.

## Look and feel

- **Motif: the jaw harp itself and "ethno" / folk craft.**
  - Use the lyre- or horseshoe-shaped forged frame with its thin steel reed (tongue).
  - Use hand-forged iron, brass, wood, leather, bone and woven or embroidered textiles, and
    folk ornament.
  - Draw on the instrument's traditions: Central European (Czech/Austrian) folk, the Siberian
    Sakha khomus, the Indian morsing and Southeast Asian bamboo and brass harps.
- **macOS 26 "Liquid Glass".**
  - Combine the crafted, ethnic artwork with Apple's new translucent glass material: glass
    panels, glass segmented controls and glass buttons floating over the artwork.
  - It must feel like a modern Mac app, not a 2005 skeuomorphic plug-in.
- Controls must be clearly usable: high contrast for labels and values, and knobs that read
  at a glance.

## Deliverables

Make **four clearly different concepts**. Vary the palette, the materials, the ornament and
how much glass versus artwork is used. For example:
1. warm forged iron and carved wood with Central European folk ornament;
2. dark Siberian khomus with silver, bone and northern ornament;
3. warm brass and deep colours inspired by the Indian morsing;
4. a restrained, modern, mostly-glass design where the jaw harp's silhouette and a single
   ornament band carry the theme.

These are suggestions only: if you have better ideas, make four strong, distinct ones.

For each concept, create two images at landscape 16:10 and save them as:
- `concept-1-keyboard.png`, `concept-1-pads.png`
- `concept-2-keyboard.png`, `concept-2-pads.png`
- `concept-3-keyboard.png`, `concept-3-pads.png`
- `concept-4-keyboard.png`, `concept-4-pads.png`

Then write `concepts.md` with a short section per concept:
- its name and idea;
- the palette (hex values);
- the materials and ornament;
- the typography;
- which parts would be **raster artwork** (background, logo, knob caps, ornament bands)
  and which would be **native SwiftUI / Liquid Glass controls**.

The chosen concept will be implemented in SwiftUI on macOS 26, with its artwork generated as
separate assets later.

Your image tool's automatic staging of generated images under `$CODEX_HOME/generated_images/`
is fine: copy the final PNGs from there into the current directory under the names above.
Apart from that staging, write nothing outside the current working directory. Do not stop
to ask questions: make sensible choices and note them in `concepts.md`.
