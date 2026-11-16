# Brumle — an app icon and a website look

Brumle is a synthesized jaw harp for macOS 26: an app and an Audio Unit. Its window wears
the "Polar Khomus" look: see `reference/concept-2-keyboard.png`, `reference/concept-2-pads.png`
and the panel's artwork in `reference/` (`background.png`, `khomus.png`, `logo.png`,
`knob.png`, `ornament.png`). Palette: midnight `#111C29`, slate `#24374A`, icy silver
`#CBDCE4`, bone `#E9DEC4`, aurora cyan `#67D6D3`. Mood: a Sakha khomus in silver and bone over
dark leather and fur, northern diamond ornament (a craft-inspired abstraction, not a claim of
an authentic traditional pattern).

Work only in the current directory. Do not stop to ask; make choices and write them down.

## Part 1 — the app icon: `AppIcon.png`

- 1024 × 1024 PNG with real transparency.
- **macOS 26 must not put it on a light plate.** It does that to any icon whose shape is not
  Apple's classic macOS app tile. So draw the artwork inside exactly that tile: a rounded
  square of **824 × 824 px centred** in the 1024 canvas (100 px transparent margin on every
  side), with a continuous-corner radius of about **185 px**, opaque everywhere inside the tile,
  fully transparent outside it, plus a soft drop shadow below the tile inside the margin. No white
  or light frame, border or plate anywhere: the artwork itself fills the tile edge to edge.
  `reference/didgeridoo-AppIcon-example.png` is a sibling app's icon that macOS 26 accepts —
  match its geometry exactly (compare the alpha mask), not its artwork.
- Artwork: the silver khomus (jaw harp) as the hero, on dark midnight/slate leather with a hint of
  aurora cyan light and perhaps a thin engraved diamond motif; it must read at 16 and 32 px
  (bold silhouette, strong contrast). No text, no letters.
- `reference/old-AppIcon.png` is the placeholder it replaces.
- Generate with your image tool, then make the tile mask and shadow exact with a script
  (Python standard library only is fine, or `sips`; if you need Pillow, check it is installed
  first and say so). Verify: the four corners (0,0)…(1023,1023) and the point (50,512) are fully
  transparent; the centre (512,512) and (120,512) are opaque.

## Part 2 — the website: `docs/`

`docs/` is a copy of the project's GitHub Pages site: an overview (`index.html`), a manual
(`manual.html`) and the same two in Czech (`cs/`), styled by `assets/site.css` and
`assets/manual.css`. Today the pages look like a generic light/dark template. The author wants
**graphics on the page** and the site to wear the app's look.

1. Design a look for the site from the app: dark midnight ground, bone/silver text, aurora cyan
   for links and buttons, a serif display face for headings (as the app's wordmark — e.g. a
   system serif stack such as `"New York", ui-serif, Georgia, serif`), SF/system sans for body.
2. Make graphics for it with your image tool, saved in `docs/assets/`:
   - a **hero illustration** for the top of the overview (wide, e.g. 2400 × 1000, dark, the silver
     khomus with leather/fur and aurora light, leaving calm space for the heading and the
     download button, or designed to sit beside them);
   - a **tileable ornament band** or divider for section breaks (you may reuse/adapt
     `reference/ornament.png`);
   - optionally a subtle full-page background texture (must stay quiet behind text).
   Keep each image under ~600 KB (use JPEG for photographic art, PNG only where alpha is needed);
   no text baked into images.
3. Apply it: edit `assets/site.css` (and `assets/manual.css` only as needed so the manual
   matches — keep its `.fig`, `.view`, `.mark` figure system working and its marks positioned),
   and the HTML of `index.html` and `cs/index.html` (and, only if needed for the look, the
   manuals). **Every change to an English page goes to its Czech twin too, tag for tag** (the
   Czech text stays as it is unless a new element needs Czech words). Use the new icon on the
   site (`assets/icon.png`, 256 px, from your AppIcon). Keep every link, download URL and
   version string exactly as they are. Keep it fast: no web fonts from third parties, no JS
   frameworks.
4. It must read well at 1440 px and at 400 px wide, and respect `prefers-reduced-motion` if you
   animate anything (prefer not to).
5. Check your result yourself: render the pages with headless Chrome if available
   (`/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --headless --screenshot=…
   --window-size=1440,2400 file://…`), look at the screenshots, fix what is off. Save the
   screenshots in `shots/`.

## Deliverables

- `AppIcon.png`
- the edited `docs/` with the new images
- `shots/*.png` (overview EN at 1440 and 400 wide, CS overview at 1440, manual EN at 1440)
- `DESIGN.md`: the look in a few lines (palette roles, type, graphics, what changed in which file),
  your choices, and anything you could not do.

Your image tool's staging under `$CODEX_HOME/generated_images/` is fine; copy finals here.
Write nothing else outside this directory.
