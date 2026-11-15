# Brumle — four design concepts

Eight image-generated mockups, each saved as a 1600 × 1000 PNG (exactly 16:10). Each concept has matching keyboard and pad views. Generated with the built-in image generation tool; final files were normalized from the tool's slightly different pixel dimensions using macOS `sips`. The reusable generation brief is in [generation-prompts.md](generation-prompts.md).

## 1. Hearth & Iron

**Idea:** Central European craft warmth: a forged jaw harp on carved walnut, with smoked glass keeping the instrument controls calm and readable.

- **Palette:** walnut `#563A29`, iron `#242522`, ivory `#F3E8D5`, aged brass `#C79952`, embroidered russet `#A54D3C`.
- **Materials and ornament:** walnut grain and floral carving, hammered iron, narrow red-and-ivory folk embroidery. Brass appears in position arcs and selection highlights. The strongest artwork sits below the parameter panels.
- **Typography:** expressive humanist serif wordmark; SF Pro for section titles, labels and pad names; monospaced digits for changing values.
- **Raster artwork:** walnut background, carved floral details, jaw-harp illustration/logo emblem, embroidery bands, subtle iron knob-cap texture. Keep knob-cap art unmarked so pointers can move independently.
- **Native SwiftUI / Liquid Glass:** smoked parameter surfaces, header menus, mode switch, modulation/MIDI buttons, segmented selectors, keyboard and pads. Knob arcs, pointers, labels, values and selected-pad border are drawn live. Approximate visual emphasis: 45% craft, 55% glass.
- **Files:** [Keyboard](concept-1-keyboard.png) · [Pads](concept-1-pads.png).

## 2. Polar Khomus

**Idea:** A cool, nocturnal Sakha-khomus-inspired instrument: silver and bone over dark leather, framed by deep blue glass and cyan modulation accents.

- **Palette:** midnight `#111C29`, slate `#24374A`, icy silver `#CBDCE4`, bone `#E9DEC4`, aurora cyan `#67D6D3`.
- **Materials and ornament:** brushed silver, engraved jaw-harp frame, weathered bone, dark leather and soft fur-like background detail. Northern geometric diamonds provide the ornamental rhythm; these are craft-inspired abstractions rather than claims of authentic traditional patterns.
- **Typography:** refined angular serif wordmark and display headings; SF Pro for controls. The mockup uses serif pad names; production can retain those with sans-serif pitch/group metadata.
- **Raster artwork:** leather/bone background vignette, silver khomus and logo emblem, engraved diamond strips, brushed-metal knob-cap texture.
- **Native SwiftUI / Liquid Glass:** blue-black translucent groups, silver-edged menus and buttons, cyan selection and modulation indicators, all parameter text, rotary interaction, keyboard and pad triggers. Approximate visual emphasis: 35% craft, 65% glass.
- **Files:** [Keyboard](concept-2-keyboard.png) · [Pads](concept-2-pads.png).

## 3. Morsing / Indigo

**Idea:** The richest direction: hammered brass against indigo and aubergine textiles, with plum glass panels and warm amber performance highlights.

- **Palette:** brass `#C79542`, indigo `#202343`, aubergine `#39243E`, saffron `#E4A449`, cream `#F7EAD0`.
- **Materials and ornament:** hammered brass jaw harp, woven silk, fine gold geometric and floral borders with kolam-inspired linework. Ornament is a contemporary craft interpretation; no religious imagery is intended.
- **Typography:** editorial serif wordmark, section headings and pad names; SF Pro labels and metadata; tabular numeric values.
- **Raster artwork:** silk folds and weave, textile borders, brass morsing illustration/logo emblem, fine hammered/brushed knob-cap texture.
- **Native SwiftUI / Liquid Glass:** plum-tinted panel surfaces, menus and segmented controls, amber knob pointers and selected-pad outline, keyboard, pads, text and values. Approximate visual emphasis: 50% craft, 50% glass.
- **Files:** [Keyboard](concept-3-keyboard.png) · [Pads](concept-3-pads.png).

## 4. Reed / Glass

**Idea:** The most restrained Mac direction: pale mineral glass, graphite typography and jade accents. A ghosted jaw-harp silhouette and one woven ornament band carry the theme.

- **Palette:** mineral `#E9EEEC`, frosted white `#F8FBFA`, graphite `#25312F`, jade `#4F8579`, silver `#BCC9C5`.
- **Materials and ornament:** milky translucent glass and a restrained satin-silver harp. One narrow sage band at the bottom; no carved framing or richly patterned control backgrounds.
- **Typography:** SF Pro Rounded-style wordmark; SF Pro throughout controls and pads, using weight and spacing for hierarchy. Graphite text remains high contrast on pale surfaces.
- **Raster artwork:** faint background harp silhouette, lower silver-harp illustration and the single ornament band. The logo emblem may start as raster artwork; redraw it as a clean scalable shape for production. No raster knob caps are needed.
- **Native SwiftUI / Liquid Glass:** header, all glass surfaces and controls, procedural knob circles/pointers/arcs, jade selection states, piano keys and pads. Approximate visual emphasis: 10% craft, 90% glass.
- **Files:** [Keyboard](concept-4-keyboard.png) · [Pads](concept-4-pads.png).

## Shared design choices and implementation handoff

- The five parameter groups remain in the same order and position between modes. The brief's complete control inventory takes precedence over the approximate knob count: selectors and LFO shape menus accompany 28 rotary controls.
- All concepts use the same illustrative program (`Khomus`), preset (`Ember Pulse`) and values to make visual comparison easier. Pad 01 (`Ember`, `C2`, `G1`) is selected; upper controls represent that sound. Names, values and units are design samples, not a synthesis specification.
- Keyboard views show approximately three octaves with C2/C3/C4 landmarks and a `Send to pad` action. Pad views use exactly four columns and four rows, with number/name above pitch/mute group. Rectangular pads trade physical MPC proportions for readable metadata in the landscape window.
- Pad mode places the bank at lower left and selected-sound artwork at lower right. There is no `Send to pad` action in pad mode. The header's `MIDI` button means MIDI Learn.
- Curve's four choices are labeled 1–4 because curve definitions were not supplied. LFO shapes use Sine and Tri, with illustrative tempo-synced rates. Product work should define the curve behaviors before replacing these labels with curve icons.
- Exact 16:10 takes priority over the approximate 1100 × 700-point brief. These images scale to 1100 × 687.5 points. Production should verify text and hit-target sizes in the actual host window.
- All visible control text, including the wordmark where feasible, should be live text. Generate decorative assets separately after selection; never bake labels, numerical values, pad metadata, key labels or state highlights into background artwork.
- Rotary knobs, keyboard keys and pads are custom SwiftUI controls, with native interaction/accessibility behavior and system glass styling where appropriate. They are not assumed to be stock system widgets. Use real runtime glass for control chrome; the PNGs only illustrate its intended appearance.
- Maintain the same editor composition in the standalone app and Audio Unit host. Keep ornaments out of label regions, and provide sufficiently opaque control surfaces when transparency is reduced.

The palettes above are intended design tokens, not pixel-sampled measurements. The mockups explore visual direction; final typography, physical keyboard geometry, knob angle/value mapping and exact glass rendering should be drawn deterministically in SwiftUI.
