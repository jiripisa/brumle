# Phase 02 — Verification (2026-11-16)

The engine is not playable yet: there is no panel, no audio output and no Audio Unit (phase
04). Everything below was checked through the C interface, the `Synth` wrapper and rendered
files.

| Check | Result |
|---|---|
| `swift test` | 70 tests in 11 suites pass (10.5 s) |
| `swift test -c release` | 70 tests in 11 suites pass (2.9 s); the 24 regression references hold in both builds (debug and release render the same samples) |
| `swift test --sanitize=thread` | 70 tests pass (75.3 s), no report |
| `./build.sh debug`, `./build.sh release` | both succeed; `codesign --verify --deep --strict build/release/Brumle.app` passes |
| `build/release/Brumle.app`, opened by path | starts and runs (still the skeleton's empty window); quit afterwards |
| Prototype equivalence (32 comparisons at 96 kHz, engine vs `Tests/BrumleReference`) | worst residual −114.31 dB |
| Output level | `kLevel` 0.2: the default hit peaks at −6.04 dBFS; the limiter is transparent up to 0.6 |
| Latency | 29 host frames at 44.1 and 48 kHz (2× oversampling, 119-tap half-band, Kaiser β 9.2, 92 dB from 0.55·fs); 0 at 88.2 kHz and above. The 48 kHz render aligned with the 96 kHz render differs by less than −60 dB |
| Voices | 40 slots, at most 16 sounding; a 16-pad flood and a mixed keyboard-and-pad flood both reach 16 and never exceed it |
| Tails | Air noise fades with the reed once it is 20 dB down; the breath bias fades over the reed's last 40 dB of absolute level, so nothing steps at retire (soft hit at velocity 1, Vel Sens 100 %, Breath 100 %: −114.5 dBFS, was −34.3) |
| Posted MIDI | more than 256 events in one block wait for the next block instead of being lost |

## The author's ear

The listening renders (`Tests/BrumleCoreTests/ListeningRenders.swift`, written when
`BRUMLE_LISTEN_DIR` is set):

| Render | First listen | After the tail fix (7b60682) |
|---|---|---|
| 01 default kit groove | good, but a hum/noise in the background | approved |
| 02 Curve Step | good | approved |
| 03 Key Up Damp | good | approved |
| 04 Close by the mod wheel | good | approved |
| 05 LFO 1 on Vowel, 3 Hz | good, but a "whoosh" in the background | approved |
| 06 Pan across pads | good, but faint noise | approved |
| 07 pitch bend on Vowel | good | approved |
| 08 aftertouch on Breath | good | approved |
| 09 VEL>Ring and VEL>Vowel | good | approved |
| 10 default hit, 44.1 vs 96 kHz | good, but slight noise | approved |

The noise was the prototype's own: Air noise passed the slot after the reed had died and stayed
at a constant −59 dB under the peak (Đàn Môi −51) until the voice retired at about 6.7 s, and
the breath bias stopped as a step at retire. The fix went into the prototype, its test copy and
the engine alike (spec §5 and §8, amended 2026-11-16).

The final review's fix (e73b8ab) then made the breath fade absolute. It was not listened to
again: against the approved renders it differs by at most −30.9 dBFS peak in 08 (aftertouch on
Breath), at least 35 dB under the signal at every moment, and by −48 dBFS or less elsewhere.
Those renders are in the session's scratchpad (`listen-02c`), not in the repository.

## Deviations from the plan and the spec

- **Half-band:** 119 taps instead of the plan's 63-tap cap, latency 29 frames instead of 15:
  the shorter filter let audible aliasing through at 44.1 kHz.
- **Voice slots:** 40 instead of 20 (16 still sounding at most): with 20, a 16-pad flood cut
  fading tails hard.
- **Spec §9.1 "staggered" control-rate updates:** each voice's 16-sample countdown starts at
  its own first sample, as the prototype equivalence requires, so pads hit on the same sample
  update together. Harmless for block deadlines, which depend on the block's total work.
- **`Synth.padNote(_:)`** returns `Int?`: out-of-range pads are ignored, as in the C API.

## Not verified

- **Real time:** no audio device, no host. The audio thread's rules (no allocation, locks
  or I/O) are checked by reading and by the TSan thread test, not by a long run in a host.
- **The wheels are unsmoothed:** renders 04, 07 and 08 sounded right, but a real controller
  may zipper. Phase 04 listens with real hardware.
- **A mono bus:** with no right buffer only the left channel comes out, so hard-right pads
  vanish. Phase 04 decides (the AU offers stereo; a mono consumer should get (L+R)/2).
- **Long Damp with a 16-pad 32nd-note flood** can still cut a quiet choking tail hard;
  allowed.
- The window list could not be read through System Events (no Accessibility permission for
  the terminal); the app's process ran and was quit.
