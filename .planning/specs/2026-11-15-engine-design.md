# Brumle — design of the instrument (engine, two modes, architecture)

Status: draft for the author's approval — 2026-11-15.

Sources: the research report `.planning/research/reports/Jaw harp acoustics and playing.md`
(with its notes) and the listening prototype `.planning/research/spike/brumle_spike.cpp`.
Sibling project: `../Didgeridoo` (same author, same pipeline). Its `CLAUDE.md` and the files
named below are the pattern to follow.

Marking: **[author]** = decided by the author; **[ear]** = approved by the author's ear on the
prototype's renders; **[call]** = a call made in design, open to correction; **[builder]** =
left to whoever plans and builds.

## 1. Intent and the why

Brumle is a playable synthesized jaw harp ("brumle" in Czech). It is an AUv2 instrument for
Ableton Live, Logic and other hosts, plus a standalone macOS app, built like Didgeridoo.
**[author]** It is used **primarily for rhythm**. The author has no reference instrument or
recording of his own. The sound was chosen by ear on the prototype's renders: "everything
sounds great and believable; if our plugin can generate these sounds, it is a knockout"
**[ear]**.

What makes it special is that it is synthesized, not sampled. Sampled jaw harps crossfade
between recorded mouth positions; a synthesized mouth resonance can glide. The pitch is free,
and every hit can be shaped and frozen onto a pad.

## 2. Goals, non-goals, anti-goals

**Goals**
- **Two modes [author].**
  1. *Keyboard mode*, like Didgeridoo: MIDI notes set the pitch and the knobs shape the sound.
  2. *Pad mode*, like an MPC drum track: 16 pads, each holding its own sound (a full knob set)
     and its own pitch. A pad receives a sound **sent from keyboard mode**. Each pad is
     triggered by its own MIDI note, as in a sampler.
- **A pad hit is a frozen key press [author].** It gives exactly what pressing the same key
  with the same knobs gives in keyboard mode.
- **The prototype's sounds are the bar [ear].** Every one of the 39 renders must be reachable
  with the plug-in's knobs and programs (see §8).
- Feature parity with Didgeridoo where it applies: programs, user presets, two LFOs, a MIDI
  controller per knob with MIDI learn, Octave, the app's MIDI input and audio output settings,
  the app installing the plug-in, and Sparkle updates.
- **Minimum macOS 26 [author].** The UI uses the new system look, including Liquid Glass.

**Non-goals**
- No internal tempo-synced rhythm generator. Rhythm comes from the notes played or from a
  host pattern **[call, proposed in conversation, not contradicted]**. LFOs shape what happens
  *inside* a hit.
- No samples are shipped. The reference recordings (CC BY-SA 4.0) are for listening and
  comparison only.
- No AUv3. It would need an app extension, and so an Xcode project, which this project never
  has.
- No overtone-melody mode in which keys pick harmonics. The pitch is the reed's fundamental.

**Anti-goals** (failure even if it "works")
- The plug-in sounds different from the prototype renders the author approved.
- Pads that do not behave exactly like a key press of their frozen sound.
- Audio-thread allocation, locks or logging. This is Didgeridoo's rule and it holds here too.
- Changing a parameter identifier or its order after the first release.

## 3. Constraints

- SwiftPM and shell scripts; never an Xcode project. Swift 6.2 tools (`.macOS(.v26)`).
- One sound engine in C++ behind a C interface, shared by the app and the AU. The sound is
  changed only there.
- AUv2 on Apple's AudioUnitSDK, vendored exactly as in Didgeridoo (`ThirdParty/AudioUnitSDK`).
- Audio thread: no allocation, locks, logging or I/O. Expensive maths runs at control rate
  (every 16 samples, as in Didgeridoo). `swift test --sanitize=thread` must stay clean.
- **Identity is permanent from the first release:** parameter identifiers and their order, and
  the AU's type, subtype and manufacturer codes. Manufacturer is `JPis` as in Didgeridoo; the
  subtype is new, e.g. `Brum` **[call]**.
- Bilingual website and manual (EN and CS), CHANGELOG line per user-visible change. These are
  the project's existing rules in `CLAUDE.md`.

## 4. Approaches considered

| Approach | Trade-off | Outcome |
|---|---|---|
| **A. Model from the research**: reed as a decaying sine, slot law makes a burst per passage, the mouth as parallel resonators struck by the bursts | Follows the measured mechanism. Brightness follows stroke strength by itself, the mouth glides, and it is cheap (about 80–90 operations per voice and sample) | **Chosen by the author** |
| B. Samples | The mouth cannot glide, many recordings would be needed, and CC BY-SA complicates distribution | Rejected |
| C. Full physical model of the vocal tract | Ten times the CPU, and it is driven by mouth shapes nobody has measured | Rejected |

Order of work: **ear first [author]**. A throwaway prototype rendered A/B files for the
report's twelve questions, and the author approved them all. This document comes after that.

## 5. The sound: what one voice does [ear]

The prototype `brumle_spike.cpp` is the reference implementation of one voice. The engine
reproduces its signal path and constants. Summary:

```
note-on (pitch, velocity, knob set)
reed   a = swing * exp(-t/tau) * choke;  x = dir * a * cos(phase)       tau = Ring / 6.91
       released at full deflection; dir = stroke direction (out / in / alternating per note)
       swing = 1 - VelSens * (1 - velocity), varied by Vary
slot   u = Edge * x + Offset (+ Clang: a term at 6.27 x the reed's phase, decaying with a
       20 ms time constant; ported exactly as the prototype computes it, wrapping phase included)
       v = -dir * a * sin(phase)                         (speed as a share of a full stroke)
       b = 0.5 * Breath + 0.5 * puff(t)                  (puff: Puff * velocity, Puff Time)
       burst = (1 - tanh²(u)) * (v + b) * |v + b|  + Air noise through the same gate
mouth  Vowel resonance (moving: Vowel, Sweep, Sweep Time, Curve, Reso; Close shuts it)
     + Throat resonance (Throat, Throat Tune, Open: wider and higher when open)
     + fixed high resonance near 2.8 kHz
     + Buzz * burst  +  Body * x
       resonators: trapezoidal SVF band-pass (Didgeridoo's TractResonance), updated
       every 16 samples
```

- **Choke:** a new hit on the same note, or Key Up when set to Damp, stops the old reed. It
  falls 40 dB in Damp ms.
- **Measured fit of the default hit** (prototype `--analyze`): the fundamental sits 18 dB
  under the strongest harmonic, the moving resonance carries the melody, and the upper
  harmonics die first. The crest factor is 12.8 dB against a measured 16–20 dB. This is known
  and accepted by ear.
- **Sample rate.** The prototype ran at 96 kHz. At 44.1/48 kHz, bright settings (high Edge,
  high notes) would alias. The engine therefore runs the voices at 2× when the host rate is
  below 88.2 kHz, and decimates **[call]**. How (half-band filter design) is **[builder]**.
- **Absolute level.** The renders were peak-normalised. The engine needs a fixed output scale
  so that the default hit at full velocity peaks around −6 dBFS, followed by a limiter on the
  sum, as in Didgeridoo **[call; exact value builder]**.

## 6. Parameters

One **knob set** = the parameters below. This table is the engine's parameter table; the
order is permanent from the first release. Defaults and ranges are the prototype's and the
report's §"Parameters" **[ear for those exercised by the renders; call for the rest]**.

| Section | Identifier | Name | Range | Default |
|---|---|---|---|---|
| Reed | `ring` | Ring | 0.3–15 s (log) | 4 s |
| Reed | `edge` | Edge | 3–40 | 18 |
| Reed | `offset` | Offset | −2…+2 | +0.2 |
| Reed | `body` | Body | −48…0 dB | −24 dB |
| Reed | `buzz` | Buzz | 0–100 % | 40 % |
| Reed | `clang` | Clang | 0–100 % | 10 % |
| Stroke | `velsens` | Vel Sens | 0–100 % | 70 % |
| Stroke | `vellevel` | Vel>Level | 0–100 % | 0 % |
| Stroke | `stroke` | Stroke | Out / In / Alternate | Alternate |
| Stroke | `damp` | Damp | 2–80 ms | 10 ms |
| Stroke | `keyup` | Key Up | Ring / Damp | Ring |
| Stroke | `vary` | Vary | 0–100 % | 20 % |
| Mouth | `vowel` | Vowel | 500–3300 Hz (log) | 800 Hz |
| Mouth | `sweep` | Sweep | −24…+24 st | +14 |
| Mouth | `sweeptime` | Sweep Time | 10–2000 ms (log) | 160 ms |
| Mouth | `curve` | Curve | Glide / Line / There and back / Step | Glide |
| Mouth | `reso` | Reso | Q 4–40 | 15 |
| Mouth | `throat` | Throat | −30…0 dB | −10 dB |
| Mouth | `throattune` | Throat Tune | 250–700 Hz | 430 Hz |
| Mouth | `open` | Open | 0–100 % | 30 % |
| Mouth | `close` | Close | 0–100 % | 0 % |
| Breath | `breath` | Breath | −100…+100 % | +30 % |
| Breath | `puff` | Puff | 0–100 % | 30 % |
| Breath | `pufftime` | Puff Time | 20–1000 ms (log) | 120 ms |
| Breath | `air` | Air | 0–100 % | 10 % |
| Master | `volume` | Volume | −40…+6 dB | 0 dB |
| Master | `pan` | Pan | −100…+100 % | 0 |
| Master | `tune` | Tune | −100…+100 cents | 0 |
| Master | `octave` | Octave | −2…+2 | 0 |
| Master | `bendvowel` | Bend>Vowel | 0–24 st | 12 |
| Master | `lfostart` | LFO Start | Hit / Free | Hit |
| LFO | `lfo1rate`, `lfo1shape`, `lfo2rate`, `lfo2shape` | LFO 1/2 | as in Didgeridoo | 6 Hz sine, 2 Hz sine |

- After these come the LFO amounts, one per LFO and target, as in Didgeridoo
  (`didge_lfo_amount`). Targets: Vowel, Close, Breath, Open, Reso, Throat, Buzz, Body, Volume,
  Edge, Offset **[call, from the report]**. Each voice carries its own LFO phase. With
  LFO Start = Hit, a hit repeats exactly, which the pad rule needs.
- **Velocity [ear: both renders 11_A and 11_B approved, so both behaviours stay].**
  - Vel Sens scales the swing, as `swing = 1 - VelSens * (1 - velocity)`. It also scales the
    Puff, as `puff * (1 - VelSens * (1 - velocity))`. At the default 70 % this equals the
    prototype's `0.3 + 0.7 * velocity`.
  - Vel>Level scales the output level, as `1 - VelLevel * (1 - velocity)`.
  - Render 11_B ("level only") is Vel Sens 0 % with Vel>Level 100 %. The prototype's
    `levelOnlyVelocity` flag maps onto these two knobs, and every render stays reachable
    **[call]**.
- `pan` makes the output stereo. Didgeridoo is mono **[call: a pad instrument benefits from
  placing pads; default centre keeps the prototype's sound]**.
- Not yet heard by the author: Curve Step, Key Up = Damp, Close, the LFOs, Pan and the wheels.
  Each is checked by ear in the phase that adds it.
- Wheels: pitch bend moves the Vowel (Bend>Vowel), the mod wheel moves Close, and aftertouch
  moves Breath. They act on the keyboard set, not on ringing pad voices **[call, from the
  report]**.

## 7. The two modes

**Mode** is a global switch (Keyboard / Pads), saved with the state (app settings, host
project and user presets). It is not an automatable parameter **[call]**.

**Keyboard mode**
- Every MIDI note plays the **keyboard set**, the knob set the panel shows, at the note's
  pitch: Octave and Tune apply, and C2 at Octave 0 is 65.4 Hz.
- **One voice per note number.** The same note again chokes its own ring and plucks anew.
  Different notes ring over each other.
- A voice started from the keyboard set follows the knobs while it rings.

**Pad mode**
- **Notes 36–51 (C2–D♯3)** trigger pads 1–16 (MPC and Ableton Drum Rack convention)
  **[call, proposed in conversation, not contradicted]**. Other notes are ignored.
- A pad holds a **frozen knob set plus its own pitch**, a MIDI note number. Tune and Octave
  live in the set.
- A pad voice uses its own set and does **not** follow later knob changes. Pad hits overlap
  each other. The same pad again chokes its previous hit.
- **Mute groups, as on an MPC [author].** Each pad has a **Group**: Off or 1–16. The range is
  **[call]**.
  - A hit chokes the ringing voices of every pad in the same group, whatever their pitch, and
    always its own pad's voice.
  - Group Off: the pad chokes only itself, so same-pitch pads ring over each other.
  - Stroke = Alternate alternates per group, which acts as one harp, or per pad when Off
    **[call]**.
  - Like the pitch, Group is a property of the pad, not part of its knob set. It is saved with
    the pads and the kit.
  - The default kit uses groups where pads are meant as one harp **[call]**.
- **Send to pad:** in keyboard mode, an action copies the keyboard set and the pitch of the
  last played note (C2 if none) to a chosen pad. Overwriting asks for confirmation **[call]**.
- **Editing a pad:** selecting a pad in pad mode shows its set in the panel, and knob changes
  go to that pad. Its pitch is set on the pad. Pad edits are not AU parameters (see §9).
- **Default kit:** on first launch the 16 pads hold a kit built from the programs at various
  pitches (the prototype's `14_pads_overlapping_kit` as a starting point), so pad mode sounds
  at once **[call; the kit's contents builder, approved by ear]**.
- **Kits** (all 16 pads) are saved and loaded like presets, shared by the app and the plug-in
  as files, as Didgeridoo's user presets are **[call, proposed in conversation, not
  contradicted]**.

**Voices**
- A voice knows its origin: a note number in keyboard mode, or a pad and its group in pad
  mode. Choking and stroke alternation follow the rules above.
- A pool of 16 voices shared by both modes. When full, the quietest voice is stolen with a
  few-ms fade.
- Voices that fall below a floor are retired, which also prevents denormals.

## 8. Programs [ear]

Built-in programs are knob sets, overrides of the defaults as in Didgeridoo. The seven the
author heard and approved:

- Brumle (the default)
- Molln
- Khomus
- Morsing
- Đàn Môi
- Bamboo
- Genggong

Their values are in `brumle_spike.cpp` (`main`). The report's other ideas (Trance,
Munnharpe, Talking, Drops) may be added later, each heard first.

**Acceptance bar.** For each of the prototype's scores (§5 files 01–14), the engine renders
the same score at 96 kHz.
- With `vary` = 0 and `air` = 0, the result matches the prototype's render closely. Exact
  tolerance is **[builder]**; aim at a residual far below audibility, e.g. under −60 dB.
- With Vary and Air on, it matches statistically.
- Either way, the author hears no difference. If the engine ports the prototype's random
  generators exactly, the stricter match holds throughout **[builder]**.

The prototype's renders are thereby also the first entries of `SoundRegressionTests`.

## 9. Architecture (Didgeridoo's, with these changes)

Targets, mirroring Didgeridoo (`Package.swift`, `CLAUDE.md`):

- `BrumleDSP`: the C++ engine and its C interface.
- `AudioUnitSDK`: vendored.
- `BrumleAU`: the AUv2 instrument.
- `BrumleAUView`: the plug-in's window.
- `BrumleAUExports`: the linker settings only.
- `BrumleCore`: the Swift layer, without SwiftUI.
- `BrumleUI`: the shared panel.
- `Brumle`: the app.

The core target is `BrumleCore` (never `brumle`, because of case-insensitive APFS).

Changes against Didgeridoo, from the report's §"What … does not fit":

1. **A voice pool** (16) instead of one voice; each voice owns its reed, slot, resonators,
   gesture clocks and LFO phases. Control-rate updates are staggered across voices.
2. **Seventeen knob sets:** the keyboard set plus 16 pad sets, each with its note. The C
   interface addresses a set by index (keyboard = 0, pads = 1…16) **[call; exact API
   builder]**.
3. **AU parameters = the keyboard set only.** Pad sets, pad notes, the mode and the kit go
   into the AU's saved state (ClassInfo) as a block. Host automation is therefore defined only
   for keyboard mode **[call: 17 × ~55 ≈ 900 AU parameters would be unusable]**.
4. **No amplitude envelope.** The reed's swing is the envelope. There is no
   Attack/Release/Glide and no Rhythm section.
5. **Events, not a drone:** every hit restarts its gesture and, with LFO Start = Hit, its
   LFOs. Random variation comes from generators reset with the engine, so that regression
   references hold.
6. **2× oversampled voices** below 88.2 kHz host rates (§5).
7. **Stereo output** for Pan.
8. Regression scores include overlapping pads, two same-pitch pads with Group Off and in one
   group, a re-struck note, a damped note and both stroke directions. Didgeridoo's `#pragma clang fp contract(off)` lesson applies.

These carry over unchanged:
- the C interface over C++;
- sample-accurate MIDI;
- lock-free parameter and MIDI queues;
- the 16-sample control interval;
- the trapezoidal resonator;
- programs as overrides;
- MIDI controllers per keyboard-set knob with learn;
- user presets as files;
- the app's audio output, MIDI input and settings;
- installing the AU from the app;
- auval validation.

## 10. The panel and Liquid Glass

What the UI must offer:
- Both modes and the mode switch.
- The keyboard-set knobs in their sections.
- Program, preset and kit menus.
- Send to pad.
- 16 pads you can click, select and edit, each with its pitch.
- LFO amounts on knobs and MIDI learn, as in Didgeridoo.
- An on-screen keyboard in the app.

The same panel serves the app and the plug-in, as Didgeridoo's `BrumleUI`/`InstrumentPanel`
pattern does.

**The look is the author's to decide.** It is designed in its own short brainstorm, with
mockups, before the panel is built. Didgeridoo's raster skin (Codex artwork and a custom
`KnobView`) is not carried over: it works against Liquid Glass's system materials. **[call;
look: author]**

## 11. Proposed phases [call]

Each phase has its own PLAN.md, branch and merge (development_workflow.md §4).

1. **02-engine:**
   - macOS 26 bump: `Package.swift` tools 6.2 and `.macOS(.v26)`, `LSMinimumSystemVersion`,
     README, CLAUDE.md and the website's "macOS 14" lines in EN and CS.
   - `BrumleDSP` with the voice pool, 17 sets, modes, programs, LFOs and oversampling.
   - The `BrumleCore` wrapper.
   - Tests: the prototype equivalence (§8), regression scores and TSan.
2. **03-panel-design:** the Liquid Glass panel's look decided with the author (design only).
3. **04-app-and-audiounit:**
   - the app (audio out, MIDI in, settings, on-screen keyboard and pads);
   - the AUv2 with its view;
   - both modes, Send to pad and pad editing;
   - auval;
   - the manual in EN and CS.
4. **05-presets-kits-midi-learn:** user presets, kits, MIDI controllers and learn.
5. **06-v0.1.0-release** via the project's `release` skill.

## 12. Left to the builder

- The C API's exact shape for sets, modes and pads.
- The half-band decimator.
- The output scale and the limiter.
- The voice-stealing details.
- The tolerance of the equivalence test.
- The default kit's contents (to be approved by ear).
- The `BrumleCore` types.
- Test structure.
- Everything Didgeridoo already solves the same way.
