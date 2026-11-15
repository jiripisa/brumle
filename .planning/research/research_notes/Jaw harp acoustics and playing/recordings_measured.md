# What eleven recordings of real jaw harps measure (this research's own analysis)

Everything in this file was **measured in this research** on 2026-11-15, on public recordings, with scripts written for the purpose. It is unpublished and unreviewed, nobody listened to the recordings while it was done (the analysis ran without audio playback), and the onset detector was checked only against printed envelope traces. Treat every number as "one player family, one microphone, one take per instrument". It exists because the literature gives few numbers for the things a pluck synthesizer needs most: how long a pluck rings, how its brightness falls, how fast strokes follow each other, what precedes a re-pluck, and how sharp the mouth's resonance is.

## 1. The recordings and the method

### Takeaway
Eleven mono WAV files (48 kHz, 16 bit) from one Wikimedia Commons series, recorded 26–27 July 2024 in Molln (Upper Austria) at the Wimmer-Bades jaw harp workshop: eight single instruments from six traditions and three takes of Alpine playing on several harps. Licence CC BY-SA 4.0 (author "DrTrumpet", players Roland and Florian Bades).

### The files
All are in [Category: Maultrommel Manufaktur Wimmer-Bades](https://commons.wikimedia.org/wiki/Category:Maultrommel_Manufaktur_Wimmer-Bades). Three file pages were read in full for player, date and licence (marked †); the others belong to the same series and were not read one by one, so their player and licence are assumed from the series.

| # | File (Wikimedia Commons) | Instrument as the title names it | Length |
|---|---|---|---|
| 1 | [Klangdemonstration einer jakutischen Maultrommel.wav](https://commons.wikimedia.org/wiki/File:Klangdemonstration_einer_jakutischen_Maultrommel.wav) † | Yakut khomus; played by Roland Bades; "Neumann TLM 102 Studiomikrofon (Großmembran Kondensator, Niere) mit Zoom H6 Recorder" | 50.7 s |
| 2 | [… - der Khomus aus Sibirien.wav](https://commons.wikimedia.org/wiki/File:Klangdemonstration_einer_jakutischen_Maultrommel_-_der_Khomus_aus_Sibirien.wav) | by its numbers the last 17.2 s of file 1 (same fundamental, and its final decay reads within 1–2 dB of file 1's at every 100 ms step); used only for the stroke statistics of its fast passage | 17.2 s |
| 3 | [… vietnamesischen Maultrommel - Dan Moi Jew's Harp - aus Eisen.wav](https://commons.wikimedia.org/wiki/File:Klangdemonstration_einer_vietnamesischen_Maultrommel_-_Dan_Moi_Jew%27s_Harp_-_aus_Eisen.wav) | Vietnamese đàn môi "of iron" | 15.2 s |
| 4 | [… nepalesischen Maultrommel.wav](https://commons.wikimedia.org/wiki/File:Klangdemonstration_einer_nepalesischen_Maultrommel.wav) | Nepalese harp | 5.2 s |
| 5 | [… mongolischen Maultrommel.wav](https://commons.wikimedia.org/wiki/File:Klangdemonstration_einer_mongolischen_Maultrommel.wav) | Mongolian harp | 5.6 s |
| 6 | [… sizilianischen Maultrommel.wav](https://commons.wikimedia.org/wiki/File:Klangdemonstration_einer_sizilianischen_Maultrommel.wav) | Sicilian harp | 5.8 s |
| 7 | [… indischen Maultrommel.wav](https://commons.wikimedia.org/wiki/File:Klangdemonstration_einer_indischen_Maultrommel.wav) † | Indian harp, "aus Messing gegossen und mit einem Pfau verziert", "beim Spielen auf Zahnreihen aufgelegt"; Roland Bades | 10.7 s |
| 8 | [Klangdemonstration Mollner Maultrommel - sehr hoher Ton auf d3.wav](https://commons.wikimedia.org/wiki/File:Klangdemonstration_Mollner_Maultrommel_-_sehr_hoher_Ton_auf_d3.wav) | Molln harp, "very high tone on d3" | 10.1 s |
| 9 | [… - Wechselspieltechnik - Vokale auf Ton c2.wav](https://commons.wikimedia.org/wiki/File:Klangdemonstration_Mollner_Maultrommel_-_Wechselspieltechnik_-_Vokale_auf_Ton_c2.wav) † | Molln harp, "vowels on tone c2"; Florian Bades | 7.4 s |
| 10 | [… - Wechselspieltechnik auf den Tönen c, d, g.wav](https://commons.wikimedia.org/wiki/File:Klangdemonstration_Mollner_Maultrommel_-_Wechselspieltechnik_auf_den_T%C3%B6nen_c,_d,_g.wav) | three Molln harps played in alternation | 36.6 s |
| 11 | [… - Einfaches Lied - O du lieber Augustin - Wechselspieltechnik auf den Tönen A und E.wav](https://commons.wikimedia.org/wiki/File:Klangdemonstration_Mollner_Maultrommel_-_Einfaches_Lied_-_O_du_lieber_Augustin_-_Wechselspieltechnik_auf_den_T%C3%B6nen_A_und_E.wav) | two Molln harps, a simple song | 22.4 s |

Two further takes of the series ("Wechselspieltechnik Improvisation", "… volkstümlicher Spielweise") could not be downloaded (HTTP 429) and are not in the analysis.

### Method (so that it can be repeated)
- Tools: Python's standard library only (`wave`, a radix-2 FFT written out), because the machine had no numpy, ffmpeg or sox; `afconvert` made 24 kHz copies for the spectral part. The scripts lived in the session's scratch folder and are not kept.
- **Fundamental**: a comb over the long-term spectrum (16384-point Hann frames at 24 kHz, 1.46 Hz bins): the mean of (level at k·f) minus (level midway between), k up to 6 kHz; the lowest candidate scoring within 85 % of the best, refined by parabolic interpolation on the ten strongest harmonics. Multiples of the true fundamental score as well as the fundamental itself (every harmonic is strong), so the choice was checked against the harmonic table for every file and **forced by hand for files 1/2 (73.14 Hz) and 6 (63.84 Hz)**, where the automatic pick was the third harmonic.
- **Harmonic levels**: 2048-point Hann frames (85 ms) every 20 ms at 24 kHz; the power of harmonic k is the sum of 3 or 5 bins around k·f0. "Sounding frames" are those within 30 dB of the loudest.
- **Onsets**: an envelope of the largest |x| within two periods of the lamella, every 1 ms at 48 kHz; an onset is a rise of at least 6 dB over 3 ms that ends at least 8 dB above the lowest level of the 13 ms before it. This finds strokes that follow a dip; a soft stroke on a ringing reed that raises the level by less than 8 dB is missed.
- **Decay**: straight-line fits of level (dB) against time for groups of harmonics, between strokes at least 300 ms apart (from 70 ms after one to 100 ms before the next), and readings of the longest gap of each file at 100 ms steps.
- **Mouth resonance**: per sounding frame, the strongest harmonic between 300 Hz and 4.5 kHz, how far it stands above its neighbours, and separately the strongest harmonic in 250–700 Hz and in 700–4500 Hz.
- **Pulse structure**: stretches of 140–300 ms were high-passed (second difference, which weighs 4 kHz and above), squared and folded over the lamella's period (refined per stretch by autocorrelation in 0.05 % steps) into 48 bins.

## 2. The lamella's fundamental and its harmonics

### Takeaway
The eight instruments have fundamentals of 64–146 Hz. The sound is a strictly harmonic series on that fundamental (the strongest partials sit within a few cents of whole multiples), but the fundamental itself is weak: 17–31 dB under the strongest harmonic on average, and 17–32 dB under the harmonic the mouth is bringing out at any moment. The makers' note names are scientific-pitch names of the lamella's fundamental ("c2" = 66 Hz, "d3" = 146 Hz, the latter called "very high").

### Measured
| # | Instrument | f0 | Nearest note | Harmonics above the level midway between them (median, to 5 kHz) | Odd (1–19) against even (2–20) harmonics, mean dB re strongest | Slope of the max-hold harmonic envelope, 0.5–5 kHz |
|---|---|---|---|---|---|---|
| 1 | Yakut khomus | 73.1 Hz | D2 −8 cents | 14.3 dB | −11.1 / −10.5 | −6.3 dB/oct |
| 3 | đàn môi (iron) | 78.9 Hz | D#2 +24 cents | 12.9 dB | −11.4 / −10.5 | −7.1 dB/oct |
| 4 | Nepalese | 109.4 Hz | A2 −10 cents | 24.3 dB | −16.1 / −11.4 | −3.8 dB/oct |
| 5 | Mongolian | 99.3 Hz | G2 +23 cents | 25.5 dB | −16.2 / −11.4 | −7.9 dB/oct |
| 6 | Sicilian | 63.8 Hz | C2 −43 cents | 16.3 dB | −16.8 / −14.2 | −9.5 dB/oct |
| 7 | Indian (cast brass) | 129.4 Hz | C3 −19 cents | 22.6 dB | −8.8 / −7.9 | −3.9 dB/oct |
| 8 | Molln "d3" | 146.1 Hz | D3 −9 cents | 14.1 dB | −16.7 / −10.6 | −4.2 dB/oct |
| 9 | Molln "c2" | 66.0 Hz | C2 +16 cents | 19.3 dB | −11.9 / −10.3 | −9.1 dB/oct |

- **Harmonicity.** For each file the ten strongest partials of the long-term spectrum lie within ±5 cents of k·f0, most within ±2 cents; the two exceptions are +7.3 cents (khomus, k = 6) and −7.4 cents (đàn môi, k = 18). The method resolves about 1–3 cents. The level midway between the harmonics lies 13–25 dB under them (table, median), so there is no second series between them, such as one an octave under the chosen fundamental. A search of the long-term spectra for peaks lying more than 0.22·f0 away from every harmonic found only small ones, 10–20 dB above their surroundings and 15–49 dB under the strongest harmonic. Three files have one at 6.2–6.5 times the fundamental, near the 6.27 of a uniform clamped bar's second mode: 681 Hz = 6.23·f0 at −43 dB (Nepalese), 911 Hz = 6.24·f0 at −28 dB (Molln d3), 508 Hz = 6.45·f0 at −32 dB (đàn môi). With dozens of such bumps per file this is suggestive only; the other five files show none there. The largest off-series peak of all is 813 Hz (12.32·f0, −20 dB) in the Molln c2 take, unexplained (the player of that take alternates harps, so another harp ringing along is possible).
- **Low harmonics are weak** (mean power over sounding frames, dB re the strongest harmonic of the file): harmonic 1: −23 (khomus), −27, −27, −30, −29, −22, −31, −17 (Molln c2); harmonic 2: −23, −28, −22, −29, −30, −10, −13, −23; harmonic 3: −22, −21, −22, −22, −32, −1, −18, −25 (same order as the table).
- **The harmonic the mouth brings out stands above the fundamental** by a median of 30.0, 28.6, 28.8, 31.9, 32.3, 26.7, 32.2 and 17.5 dB (same order; over all sounding frames).
- **Many harmonics.** In file 9 (f0 = 66 Hz) harmonics up to about the 45th (3 kHz) stay within 17 dB of the strongest, and the 60th (4 kHz) is at about −30 dB; above about 6 kHz the table flattens at −25 dB, which is the level of the stroke transients, not of harmonics.
- **Pitch does not glide.** Per-stretch periods of the Molln c2 harp: 66.01–66.04 Hz for four plucks, 66.21 Hz (+5 cents) in the first 200 ms after one pluck, 66.01 Hz 0.6 s and 1.4 s later. Sicilian: 63.76–63.82 Hz, 63.50 Hz (−8 cents) one second into the last decay. Resolution 0.9 cents.

- **Odd against even harmonics: no single answer in these recordings.** In the plain mean of dB values over the first twenty harmonics the even ones are 0.6–6.1 dB stronger (table). Looked at by region (how far a harmonic stands above the mean of its two neighbours, in the long-term spectrum, averaged over the odd and over the even harmonics of the region) the lead changes: Mongolian harp, even harmonics +9 dB at harmonics 11–20 and +7 dB at 21–30; Nepalese, even +7 dB at 2–10 but odd +4 dB at 21–30 and +7 dB at 31–45; Molln d3, even +6 and +5 dB up to harmonic 20; khomus, đàn môi, Sicilian, Indian and Molln c2, within ±2 dB almost everywhere, changing sign from region to region. The published statements (odd harmonics stronger: Leipp, Vandré, Li, Nikolsky; see the reed notes) are not borne out here as a general rule. These players hold the instrument at the mouth and probably breathe through it, which the literature says adds even harmonics; and two unequal bursts that are not exactly half a period apart make a comb whose leading parity alternates along the spectrum.

### Inferences (mine)
- The pitch a listener names must come from the harmonic series as a whole (the "missing fundamental"), since the component at f0 is 20–30 dB down; a synthesizer that mixes in a strong sine at the fundamental as a "drone" would not match these recordings.
- The max-hold envelope (each harmonic at the loudest it ever gets, which is roughly the source spectrum times the best the mouth can do for it) falls 4–9.5 dB per octave between 0.5 and 5 kHz: between a pulse train (0 dB/oct) and a sawtooth (−6 dB/oct) for the brighter instruments, a little darker than a sawtooth for the two lowest.

### Gaps
- No calibrated level: the files are normalised differently (peaks from −6 to 0 dBFS), microphone distance unknown.
- The low-frequency weakness could in part be the recording (a cardioid at unknown distance, possibly a high-pass); a TLM 102 is flat to well below 60 Hz according to its maker, but that was not checked here.

## 3. Two bursts in every period, fading as the lamella dies down

### Takeaway
Folded over the lamella's period, the energy above about 4 kHz comes in **two bursts per period, half a period apart (0.48–0.50 T), the second 5–8 dB weaker than the first**. Right after a pluck the gap between bursts is 20 dB down or more and the waveform's crest factor is 16–20 dB; 0.6–0.8 s later the bursts stand only about 10 dB above the rest, and after 1.4 s they are gone.

### Measured
- Molln c2 (f0 = 66 Hz), 60–200 ms after each of five plucks: bursts at bin 0 and bin 23 of 48 (0.48 T), second burst −8 dB; between them −16 to −24 dB. 600–800 ms after: second burst no longer distinct, floor at −9 to −12 dB. 1.4–1.7 s after: flat within 3 dB.
- Sicilian (64 Hz): second burst at 0.50 T, −7 dB; floor −17 to −26 dB; one second into the last decay the bursts stand only 5–10 dB above the floor.
- Nepalese (109 Hz): second burst at 0.48–0.50 T, −6 dB. Mongolian (99 Hz): at 0.50 T, −5 dB.
- Crest factor (peak against RMS) of the unfiltered stretches: Molln c2 16.0–20.3 dB at 60–200 ms after the pluck, 12.6–16.6 dB at 600–800 ms, 12.8 dB at 1.4–1.7 s; Sicilian 11.3–18.3 dB; Nepalese 10.2–13.4 dB; Mongolian 11.7–14.4 dB. (A sine has 3 dB, a sawtooth 4.8 dB.)
- Whether the two bursts have the same sign or opposite signs was not settled: the autocorrelation of first-differenced stretches near T/2 swings between about +0.1…+0.9 and −0.1…−0.5 from stretch to stretch, because each burst rings the mouth's resonance.

### Inferences (mine)
- Two bursts per period, half a period apart, is what a lamella does that passes through the slot of its frame twice per cycle, once in each direction. The unequal size says the two passages are not alike (the lamella rests off-centre, or the two sides of the frame differ, or the breath favours one direction).
- The bursts sharpen with amplitude: the lamella crosses the slot faster when it swings wider. So brightness is tied to the lamella's amplitude and falls during the decay without any filter moving. This is the single most useful finding for a model: **drive a fixed non-linearity with a decaying sine and the right brightness contour comes out by itself**.

## 4. A pluck: instant attack, a dip before every re-pluck, 15–18 dB per second when left to ring

### Takeaway
A stroke reaches its full level within the first two periods of the lamella (the method's resolution; under 10 ms on the 109 Hz harp). Before a stroke on a reed that is still ringing, the level falls about 20–25 dB during the last 25–50 ms: the finger arrives, stops the lamella, then lets it go. Left alone at the mouth, the low harps decay by 15–18 dB per second.

### Measured
| # | Instrument | Strokes found | Interval between strokes, median (10th pct) | Level jump at a stroke, median | Level just before a re-pluck, under its level 30–150 ms earlier (and for how long it is more than 6 dB under) | Level after the stroke against 30–150 ms before it |
|---|---|---|---|---|---|---|
| 1 | khomus | 211 in 50.7 s | 159 ms (93 ms) | 23.7 dB | 23.4 dB (26 ms) | −0.2 dB |
| 2 | khomus, last 17 s | 90 in 17.2 s | 117 ms (99 ms) | 22.7 dB | 23.2 dB (25 ms) | −0.2 dB |
| 3 | đàn môi | 32 in 15.2 s | 362 ms (245 ms) | 20.6 dB | 19.7 dB (25 ms) | +1.2 dB |
| 4 | Nepalese | 15 in 5.2 s | 329 ms (269 ms) | 26.6 dB | 21.0 dB (47 ms) | +7.0 dB |
| 5 | Mongolian | 12 in 5.6 s | 325 ms (299 ms) | 28.8 dB | 21.1 dB (49 ms) | +7.6 dB |
| 6 | Sicilian | 11 in 5.8 s | 325 ms (311 ms) | 24.4 dB | 21.0 dB (36 ms) | +4.5 dB |
| 7 | Indian | 26 in 10.7 s | 363 ms (301 ms) | 29.4 dB | 23.7 dB (45 ms) | +5.5 dB |
| 8 | Molln d3 | 73 in 10.1 s | 113 ms (100 ms) | 24.6 dB | 24.6 dB (35 ms) | 0.0 dB |
| 9 | Molln c2 | 5 in 7.4 s | 1128 ms | 35.7 dB | 16.5 dB (50 ms) | +23.3 dB |
| 10 | Molln, three harps | 94 in 36.6 s | 293 ms (188 ms) | 26.4 dB | 18.3 dB (32 ms) | +6.8 dB |
| 11 | Molln, two harps | 51 in 22.4 s | 438 ms (169 ms) | 37.3 dB | 21.9 dB (40 ms) | +13.0 dB |

- **Stroke rates.** The fast passages (khomus, Molln d3) run at a median of 113–117 ms between strokes (8.5–8.8 per second), with a tenth of the intervals at or under 93–100 ms (10 per second). The demonstration takes of the other harps sit at about 3 strokes per second.
- **Attack.** In every file the median stroke reaches 90 % of the largest level of its first 80 ms within the first two-period step (14–31 ms depending on pitch). A trace of the Nepalese harp with 2 ms windows shows the level going from about −30 dB to its peak in 4–8 ms.
- **No bright click.** The share of 5–20 kHz against 0.2–5 kHz in the 11 ms at the onset is only −1.1 to +5.9 dB (medians per file) above the same share 60 ms later.
- **Let ring** (longest gap of each file, all harmonics together): Molln c2 18 dB/s over 1.9 s; khomus 16 dB/s over 1.9 s (then cut off); đàn môi 17 dB/s over 1.8 s; Sicilian 15 dB/s over 1.3 s (then faster). That is a 60 dB decay time of 3.3–4.1 s and an amplitude time constant of 0.47–0.59 s. The two higher harps were followed only briefly and may have been stopped by the player: Mongolian 32 dB/s over 0.8 s, Indian 35 dB/s over 0.4 s.
- **High harmonics die first.** Between strokes at least 300 ms apart, the median slopes of harmonics 2–4 / 5–10 / 11 and up are −5.8 / −8.5 / −20.0 dB/s (Molln c2), −3.8 / −7.6 / −21.4 (Sicilian), −2.9 / −8.1 / −45.8 (Nepalese), +3.0 / −16.3 / −33.3 (Mongolian). The fundamental alone: −8.5, −7.3, −7.1, −2.3 dB/s.
- In the dense khomus and Indian takes the level between detected strokes rises as often as it falls (median slope near zero or positive), so something re-energises the reed without an 8 dB jump: soft strokes, or breath.

### Inferences (mine)
- The dip before a re-pluck is a physical necessity (a finger cannot pluck a moving lamella without first catching it), so in fast playing every stroke is preceded by 25–50 ms of choking. A MIDI instrument cannot look ahead; the nearest equivalents are a fast choke of the old hit at the new note-on, or damping at note-off (the key's release is the finger landing on the reed).
- In fast playing the new stroke is no louder than the reed was before the finger landed (0 dB for the khomus and Molln d3 takes); in slow playing it is 5–23 dB louder, because the reed has decayed in between. A retrigger must therefore not add its level to what is ringing.
- A single amplitude envelope is not enough: the upper harmonics fall 2.5–6 times faster (in dB/s) than harmonics 5–10. The burst mechanism of section 3 explains this without a second envelope.

### Gaps
- No free decay in air, no decay with the mouth closed or with the glottis open: only "at the mouth, as played".
- Stroke direction (inward, outward) cannot be told from the audio by this method. Breath, tongue and glottal articulations that do not produce an 8 dB jump are invisible to it.

## 5. The mouth: one resonance near 400 Hz that stays, one that moves over 0.7–3.3 kHz

### Takeaway
Every instrument shows a lower peak that hardly moves (strongest harmonic of the 250–700 Hz band: median 290–510 Hz, mostly 390–460 Hz) and an upper peak that the player moves between about 700 Hz and 3.3 kHz (median 1.25–1.75 kHz). The upper peak usually leads by 7–20 dB. The harmonic on the upper peak stands 5–15 dB above its next neighbours, which implies a resonance roughly 70–120 Hz wide.

### Measured
| # | Instrument | Lower peak, 5th / median / 95th pct | Upper peak, 5th / median / 95th pct | Upper against lower, median | Strongest harmonic above the mean of its next neighbours, median (90th pct) | … above the mean of those two away, median (90th pct) |
|---|---|---|---|---|---|---|
| 1 | khomus | 292 / 512 / 658 Hz | 804 / 1608 / 3289 Hz | +19.0 dB | 12.0 (22.9) dB | 5.2 (12.2) dB |
| 3 | đàn môi | 315 / 394 / 631 Hz | 710 / 1262 / 2208 Hz | +13.1 dB | 7.7 (17.2) dB | 9.1 (15.1) dB |
| 4 | Nepalese | 328 / 437 / 437 Hz | 1312 / 1531 / 2515 Hz | −1.1 dB | 14.6 (22.6) dB | 15.5 (20.9) dB |
| 5 | Mongolian | 397 / 397 / 695 Hz | 894 / 1291 / 1787 Hz | +7.1 dB | 14.6 (21.6) dB | 10.5 (21.9) dB |
| 6 | Sicilian | 319 / 447 / 574 Hz | 957 / 1276 / 2170 Hz | +20.0 dB | 5.1 (16.2) dB | 7.7 (13.1) dB |
| 7 | Indian | 259 / 388 / 647 Hz | 906 / 1553 / 3364 Hz | +7.7 dB | 9.5 (15.9) dB | 13.2 (22.3) dB |
| 8 | Molln d3 | 292 / 292 / 438 Hz | 1022 / 1753 / 3067 Hz | +16.8 dB | 15.1 (22.6) dB | 6.9 (16.0) dB |
| 9 | Molln c2 | 396 / 462 / 660 Hz | 792 / 1254 / 2508 Hz | +8.6 dB | 6.0 (11.4) dB | 10.3 (13.5) dB |

- **Harmonic numbers in use.** The upper peak sits on harmonics 11–45 of the 73 Hz khomus, 9–28 of the 79 Hz đàn môi, 12–38 of the 66 Hz Molln harp, 7–21 of the 146 Hz Molln harp (5th–95th percentiles).
- **The vowel take** (file 9: five plucks about a second apart on one harp, the mouth held still after each): the upper peak holds at 1188 Hz (harmonic 18), then 1782 Hz (27), then 2376–2574 Hz (36–39), then 1386 Hz (21) with the lower peak at 396–462 Hz almost as strong, then 792–924 Hz (12–14). The lower peak is at 396–462 Hz throughout. The title promises vowels; which vowel each pluck is was not heard, so no vowel names are attached here.
- **How fast the upper peak moves.** Over 100 ms spans it had moved in 31–76 % of cases; where it moved, the median speed was 1.2–2.2 octaves per second (5.0 in the fast Molln d3 take) and a tenth of the moves exceeded 4.5–6.9 octaves per second (10.7 in the Molln d3 take). An 85 ms analysis window blurs anything faster.
- **Width.** Taking the resonance as a single two-pole peak centred on the strongest harmonic, the levels of the harmonics one and two steps away imply a −3 dB width of (median, from the next neighbours / from those two away) 77 / 85 Hz (Molln c2), 85 / 116 Hz (Sicilian), 71 / 118 Hz (đàn môi), 92 / 116 Hz (Indian). In the other four files the two estimates disagree by a factor of 2 to 6 (38 / 191, 41 / 75, 38 / 125, 52 / 294 Hz) because neighbouring harmonics alternate in strength there, so the single-peak reading does not hold.

### Inferences (mine)
- A resonance 70–120 Hz wide at 1.2–1.8 kHz is a Q of roughly 10–25. With fundamentals of 64–146 Hz that passes one to three harmonics, which is why one harmonic "sings" on the higher harps and a small cluster on the low ones.
- The alternating strength of neighbouring harmonics in half of the files is what two unequal bursts per period would do (a comb across the harmonics whose phase depends on how far from half a period the bursts are); it comes from the source, not from the mouth.
- For a synthesizer the lower peak can be nearly fixed (about 400–450 Hz, 7–20 dB under the upper one) and the upper peak is the "vowel" control, 700 Hz to about 3.3 kHz.

### Gaps
- Nothing here separates tongue, lips, jaw, larynx or breath; the audio shows only the result.
- No player other than the two makers, no morsing as played in South India, no Norwegian or Hungarian instrument, no bamboo idioglot harp (the đàn môi here is called iron), and no fast rhythmic playing by a specialist of any tradition.
- The width estimate assumes the peak is centred on a harmonic and that the source is locally flat; both assumptions fail part of the time.

## 6. Three candidate sources checked against these numbers (simulated, not heard)

### Takeaway
A decaying sine pushed through a "slot" non-linearity reproduces the five decay slopes of the Molln c2 harp when **each burst's size goes with the square of the lamella's speed at the crossing and its length with the inverse of that speed** (so its area goes with the lamella's amplitude). Two numbers do it: an amplitude time constant of the lamella of 1.1 s and a swing of 18 slot half-widths at the pluck. A source of constant burst area (air simply displaced through the slot) does not fit: its low harmonics stay level while the lamella dies down. The decay slopes do not say whether successive bursts alternate in sign; a signed law (a piston pressing air through a tight gap) gives the odd harmonics the literature reports, and a steady breath flow added to it gives the unequal bursts and the even harmonics.

### What was simulated (this research, unreviewed)
- Lamella: x(t) = A·sin(2π·66 Hz·t), A falling as exp(−t/τ_A) from A0 at each of five plucks (released at full deflection), choked over 8 ms during the 40 ms before the next pluck. u = x/w is the displacement in slot half-widths, v the lamella's speed as a share of its speed at the pluck, gate(u) = 1 − tanh²(u) (1 while the lamella is in the slot).
- **Source 1, "displaced air"**: the time derivative of tanh(u): a burst at each passage, alternating in sign, of constant area, of length w/(A·2π·f0).
- **Source 2, "one sign, speed squared"**: source 1 times |v|, the burst of one direction scaled by 1.33 and of the other by 0.67.
- **Source 3, "piston through a gap"**: gate(u)·(v + b)·|v + b|, b a steady breath flow as a share of the lamella's speed at the pluck. With b = 0 the bursts alternate in sign and are equal; with b = 0.17 one is larger.
- Mouth: two band-passes in parallel, 430 Hz (Q 5, gain 0.3) and 1250 Hz (Q 15), plus a trace of the bare sine. The result went through the same analysis as the recordings. All runs: τ_A = 1.1 s, A0/w = 18.

| Slope between plucks, dB/s | Molln c2, measured | Source 3, b = 0.17 | Source 3, b = 0 | Source 2 | Source 1 |
|---|---|---|---|---|---|
| all harmonics | −17.8 | −15.6 | −17.8 | −16.3 | −8.4 |
| harmonic 1 | −8.5 | −8.3 | −7.9 | −7.9 | −12.4 (the added bare sine) |
| harmonics 2–4 | −5.8 | −4.7 | −8.5 | −8.7 | +2.8 |
| harmonics 5–10 | −8.5 | −7.5 | −10.3 | −10.1 | −0.3 |
| harmonics 11 and up | −20.0 | −19.6 | −21.8 | −21.5 | −12.6 |
| odd (1–19) against even (2–20) harmonics, mean dB | −11.9 / −10.3 | −16.9 / −23.4 | −16.9 / −44.1 | −20.2 / −11.4 | −16.4 / −20.5 |
| second burst of the period against the first | −8 dB | −5 dB | 0 dB | −8 dB | about −8 dB (with a gated breath term) |

- Where all three fall short: crest factor 11–13 dB against the measured 16–20 dB right after the pluck, and a max-hold envelope falling 16–17 dB per octave (11 with A0/w = 30) against the measured 9. Two band-passes pass too little of the bursts themselves; the real sound has more above 2 kHz than two resonances let through, so a model needs a direct path or more resonances.
- None reproduces the measured near-balance of odd and even harmonics on this harp, nor the change of the leading parity from one region of the spectrum to the next (section 2).

### Inferences (mine)
- If the fundamental's level follows the lamella's amplitude, its slope of −7 to −8.5 dB/s on three of the four harps with regular plucks means **the lamella itself rings with an amplitude time constant of about 1.0–1.2 s (60 dB in 7–8 s)**, and the sound as a whole falls two to four times faster only because the bursts soften. "Decay" in a model of this kind is therefore two things: how fast the reed dies, and how far it swings past its frame.
- The speed-squared law has a plain mechanical reading that matches what Adkins is reported to say (the lamella in the slot is a piston driving the air ahead of it): flow forced through a narrow gap meets a resistance that grows with the flow, so the pressure goes with the square of the speed, with its sign. It also explains why makers find a tighter gap louder. This reading is mine; Adkins's paper was not read beyond its abstract.
- The fit rests on one instrument, one player and five plucks. The other harps agree in kind (low harmonics −3 to −8 dB/s, upper harmonics −21 to −46 dB/s) but were not fitted.
