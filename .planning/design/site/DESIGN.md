# Brumle — Polar Khomus

Midnight `#111C29` is the ground, slate `#24374A` gives quiet depth, icy silver `#CBDCE4` carries body text, bone `#E9DEC4` carries headings, and aurora cyan `#67D6D3` identifies links, buttons and manual annotations. System serif (`"New York", ui-serif, Georgia, serif`) headings echo the app wordmark; system sans keeps instructions readable. No remote fonts, animation, or runtime JavaScript.

The chosen layout pairs a large bone wordmark and existing download copy with a silver khomus still life, followed by the actual application screenshot. On small screens the illustration sits below the copy. Features use an open two-column layout and engraved diamond section dividers, not repeated cards. The manual remains a quiet reading surface. Diamond ornament is a craft-inspired abstraction, not a claim of an authentic traditional pattern.

The icon uses a bold diagonal silver khomus against full-bleed midnight leather. Its final alpha channel is copied exactly from `reference/didgeridoo-AppIcon-example.png`: 824 × 824 opaque tile bounds centred in 1024 × 1024, original continuous corners and drop shadow. No additional frame or plate. This is stronger geometric matching than estimating the corner radius.

## Files

- `AppIcon.png`: generated artwork with the reference alpha mask; `docs/assets/icon.png`: its 256 px derivative.
- `docs/assets/hero-khomus.jpg`: generated wide still life, compressed for the web.
- `docs/assets/ornament.png`: small seamless repeat adapted from the supplied ornament.
- `docs/assets/site.css`: shared palette, typography, responsive overview, ornament and focus styles.
- `docs/index.html`, `docs/cs/index.html`: identical structural additions for hero artwork and copy grouping. Existing text, links and version strings preserved.
- `docs/assets/manual.css`: only reading-surface/title refinements; figure coordinates and geometry preserved. Manual HTML unchanged.
- `tools/`: reproducible asset finishing and verification helpers.
- `shots/`: Chrome renders and icon geometry/size previews.

## Generation

Built-in image generation, using the supplied khomus and app concept as visual references. Prompts specify a single silver khomus, midnight/slate leather, cyan edge lighting, bone highlights, restrained diamond engraving and no text. Icon: square full-bleed artwork with a thick, diagonal silhouette. Hero: wide still life with instrument on the right and calm space on the left. The supplied ornament is reused for consistency with the app rather than generating a competing motif.

## Verification

- Icon checked as 1024 × 1024 RGBA. Alpha matches the accepted sibling byte for byte, including shadow; opaque bounds are `(100,100,924,924)`. All four canvas corners and `(50,512)` have alpha 0; `(512,512)` and `(120,512)` have alpha 255. Inspected 16, 32, 64, 128 and 256 px previews.
- Headless Google Chrome renders saved for EN/CS overview at 1440 and 400 px, EN manual at 1440 and 400 px, and CS manual at 1440 px. Overview captures show the full page; manual captures show the first 2400 desktop pixels (1000 mobile pixels), plus a separate annotated figure. All seven renders have zero horizontal page overflow and no failed images. Zoomed manual images intentionally extend within clipped `.view` containers.
- All original links, text and version strings preserved on all four pages; overview structures match tag for tag. Manual HTML and all 48 marker coordinates are unchanged. The shared styles preserve its 11 figures. `shots/browser-checks.json` and `shots/content-checks.txt` record results.
- Hero JPEG: 421,766 bytes; ornament PNG: 22,843 bytes; 256 px icon: 80,996 bytes. No third-party fonts or page JavaScript. No motion to disable.
- Visual review caught and fixed hero text overlap and mobile grid overflow from the build command. All required screenshots were inspected.
- Limitation: actual macOS 26 icon installation/plate behavior was not tested; exact alpha equality is verified against the supplied accepted sibling. No app bundle was supplied or changed.

Pillow 13 was installed temporarily inside this directory because the default Python lacked it. The asset finisher uses Pillow for alpha preservation, resizing and compression; standard `sips` cannot apply the reference mask and verify pixel equality in one reproducible operation. The render helper reuses an already installed Playwright package with local Chrome; there was no existing project renderer. Temporary dependencies and browser profiles were removed after verification. To rerun, install Pillow locally and pass generated source image paths to `tools/finish-assets.py`; pass an installed Playwright module path to `tools/render-site.cjs`.
