# Phase 02 — the sound engine: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Brumle's sound engine (`BrumleDSP`, C++ behind a C interface) plays the approved prototype's sounds in keyboard mode and pad mode. `BrumleCore` wraps it for Swift. No UI and no Audio Unit yet.

**Architecture:**
- The engine is a port of the listening prototype's voice (`brumle_spike.cpp`) into a 16-voice pool.
- It has 17 knob sets: the keyboard set plus 16 pads.
- Two LFOs and velocity (VEL) amounts modulate the knobs.
- Below 88.2 kHz the voices run at 2× and a half-band filter decimates.
- A test-only copy of the prototype (`BrumleReference`) renders the same scores, and the tests compare the two sample by sample.

**Tech Stack:** C++23 (SwiftPM `cxxLanguageStandard: .cxx2b`), Swift 6.2 tools, Swift Testing, macOS 26.

**Spec:** `.planning/specs/2026-11-15-engine-design.md` (the design). The pattern to mirror is `../Didgeridoo`: `Sources/DidgeridooDSP/DidgeridooEngine.cpp`, `include/DidgeridooDSP.h`, `Sources/DidgeridooCore/{Parameter,Synth,LFOs}.swift` and `Tests/DidgeridooCoreTests/{EngineTests,SoundRegressionTests}.swift`. The reference voice is `.planning/research/spike/brumle_spike.cpp`.

**Branch:**
1. Merge `design/engine` into `main` with `--no-ff`.
2. Create `feature/02-engine` from `main`.
3. Merge back with `--no-ff` at the end (development_workflow.md §4).
4. Never push without the author's explicit confirmation.

## Global Constraints

- **Platform:** `swift-tools-version: 6.2` and `.macOS(.v26)`; `LSMinimumSystemVersion` 26.0. There is never an Xcode project.
- **Audio thread:** `brumle_process` and `brumle_midi` never allocate, lock, log or do I/O. `swift test --sanitize=thread` stays clean.
- **Rounding:** every engine `.cpp` starts with `#pragma clang fp contract(off)`, before its includes (Didgeridoo's lesson). A debug and a release build then render the same samples.
- **Control rate:** expensive filter coefficients are recomputed every 16 **internal** samples. The countdown is per voice and starts at the voice's first sample, exactly as the prototype's `ctl`.
- **Permanent identity:** parameter identifiers and their order, as pinned in Task 2, are permanent from the first release.
- **Modulation defaults:** the LFO and VEL amounts all default to 0, so the approved sound is unchanged.
- **Pad numbering:** the C API counts pads from 0 to 15, so pad 1 is index 0. Its knob set is `pad + 1`; the keyboard set is 0.
- **Pad notes:** notes 36–51 trigger pads 0–15 in pad mode, and other notes are ignored there.
- **Velocity:** a note-on's velocity is `data2 / 127.0f`. A note-on with velocity 0 is a note-off. The MIDI channel is ignored (omni).
- **Code style:** code, comments, identifiers and commits are in English. Commits follow Conventional Commits with a scope (`feat(dsp): …`, `test(core): …`) and carry no AI attribution.
- **Changelog:** every user-visible change gets a line under `## Unreleased` in `CHANGELOG.md`.

## Review Focus

The inputs and conditions most likely to bite a player, each pinned by a test in the task named:

1. **Sample rate changes:** `brumle_prepare` at 44.1 kHz after 96 kHz, and back. The output stays finite, the pitch stays right and nothing from the old rate leaks. → Task 6, `rePrepareChangesRate`.
2. **Extreme knobs:**
   - All knobs at minimum, all at maximum, and Reso 40 with Vowel 3300 Hz and Sweep +24 st on note 96.
   - Expected: no NaN or Inf, and a peak of at most 1.0 after the limiter.
   - → Task 6, `extremeKnobsStayFinite`.
3. **A flood of hits:**
   - 32nd notes on all 16 pads with Ring 15 s, for 4 s.
   - Expected: at most 16 voices sound, there are no NaNs, and no step bigger than the limiter's ceiling appears between two samples.
   - → Task 6, `stealingStaysBounded`.
4. **Long silence after playing:** 20 s after the last hit, no voice is active, and the output is exactly 0, with no denormal tail. → Task 3, `silenceIsExact`.
5. **MIDI edge cases:**
   - A note-on with velocity 0 acts as a note-off.
   - A note outside 36–51 in pad mode is silent.
   - Pitch bend and the mod wheel change keyboard voices but not ringing pad voices.
   - → Task 5, `padModeIgnoresOtherNotes`, and Task 4, `wheelsLeavePadsAlone`.

---

### Task 1: macOS 26 and the prototype as a test reference

**Files:**
- Modify:
  - `Package.swift`: tools 6.2, `.macOS(.v26)`, the new targets, `cxxLanguageStandard: .cxx2b`.
  - `Resources/Info.plist:26`: `14.0` → `26.0`.
  - `README.md:5`, `CLAUDE.md:7`, `development_workflow.md:5`: "macOS 14" → "macOS 26", and Swift 6 → Swift 6.2 where the line names it.
  - `docs/index.html:39` ("for macOS 26 or later") and `docs/cs/index.html:39` ("pro macOS 26 a novější").
  - `CHANGELOG.md`: "- Requires macOS 26 or later."
- Create:
  - `Tests/BrumleReference/include/BrumleReference.h`
  - `Tests/BrumleReference/BrumleReference.cpp`
  - `Tests/BrumleCoreTests/PrototypeScores.swift`, the score builder shared with Tasks 3–5.
- Test: `Tests/BrumleCoreTests/ReferenceTests.swift`

**Interfaces:**

The task produces this header, `Tests/BrumleReference/include/BrumleReference.h`. It is C, and the prototype runs at a fixed 96 kHz:

```c
typedef struct BrumleRefParams {
    float ring, edge, offset, bodyDb, buzz, clang, velsens; int stroke;
    float damp, vary, vowel, sweep, sweeptime; int curve; float reso, throatDb, throattune,
    open, close, breath, puff, pufftime, air; int levelOnlyVelocity;
} BrumleRefParams;                       // the prototype's Params, same units (fractions, not %)
typedef struct BrumleRefEvent { double time; int note; float velocity; int params; int chokeOnly; } BrumleRefEvent;
void brumle_ref_default_params(BrumleRefParams* out);
// Renders `frames` mono samples at 96 kHz: events sorted by time, `params` indexes `paramSets`.
void brumle_ref_render(const BrumleRefEvent* events, int numEvents,
                       const BrumleRefParams* paramSets, int numParamSets, float* out, int frames);
```

It also produces `PrototypeScores.swift`:
- `struct ScoreHit { let frame: Int; let note: UInt8; let velocity: UInt8; let chokeOnly: Bool }`
- `struct Score { var hits: [ScoreHit]; var frames: Int }`
- `enum PrototypeScores`, with:
  - `static let sampleRate = 96_000.0`
  - `static func phrase(note: UInt8, sub: Int = 2, chokeAhead: Double = 0) -> Score`
  - `static let phraseLength: Double`
  - `static func velocity(_ accent: Float) -> UInt8`: `UInt8((accent * 127).rounded())`
  - `static func referenceParams(_ overrides: [String: Float]) -> BrumleRefParams`. It takes engine identifiers and plain engine values (%, dB, Hz), and divides the percent ones by 100.
  - `static func referenceRender(_ score: Score, params: [BrumleRefParams], paramOf: (ScoreHit) -> Int) -> [Float]`

- [ ] **Step 1: Write the failing test**

```swift
@Suite("Reference") struct ReferenceTests {
    @Test("The prototype renders its default phrase, and renders it the same twice")
    func defaultPhrase() {
        let score = PrototypeScores.phrase(note: 36)
        let params = [PrototypeScores.referenceParams([:])]
        let a = PrototypeScores.referenceRender(score, params: params) { _ in 0 }
        let b = PrototypeScores.referenceRender(score, params: params) { _ in 0 }
        #expect(a == b)
        #expect(a.count == Int((PrototypeScores.phraseLength * 96_000).rounded(.down)))
        #expect((a.map(abs).max() ?? 0) > 0.01)
    }
    @Test("Percent knobs become the prototype's fractions")
    func percentConversion() {
        let p = PrototypeScores.referenceParams(["buzz": 70, "breath": -30, "body": -10, "stroke": 0])
        #expect(p.buzz == 0.7 && p.breath == -0.3 && p.bodyDb == -10 && p.stroke == 0)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails.** Run `swift test --filter ReferenceTests`. Expected: a build error, because `PrototypeScores` and `BrumleRefParams` are undefined.

- [ ] **Step 3: Write `BrumleReference.cpp`.**
  - Copy `.planning/research/spike/brumle_spike.cpp` lines 14–221 verbatim: the includes, `SR`, `Params`, `Reso`, `dbToGain`, `kHarmonicRef`, `Voice`, `Event` and `render`.
  - Add the two `extern "C"` functions:
    - `brumle_ref_default_params` copies a default `Params` into the C struct.
    - `brumle_ref_render` builds a `Score` from the events (`Event{time, note, velocity, paramSets[params] converted, chokeOnly}`), calls `render(score, frames / SR)`, and copies at most `frames` samples into `out`.
  - Change no line of the copied code.
  - Add the package target:

    ```swift
    .target(name: "BrumleReference", path: "Tests/BrumleReference")
    ```

    Add it to the test target's dependencies.

- [ ] **Step 4: Write `PrototypeScores.swift`.**
  - `phrase` ports the spike's `phrase()` (lines 253–268) with frames instead of seconds:
    - the first hit at `0.2 * 96000`;
    - steps of `60/112/sub` s, each hit's frame rounded up to a whole frame: `Int((t * 96_000).rounded(.up))`;
    - the accent tables `kAcc8`/`kAcc16` through `velocity(_:)`;
    - the choke-only events.
  - `phraseLength` is `2.7 + 2 * 4 * 60.0 / 112.0 + 1.5`.
  - `referenceRender` passes each hit with `time: Double(frame) / 96_000` and `velocity: Float(velocity) / 127`. This makes the prototype and the engine start every hit on the same frame with the same velocity.
  - `referenceParams` maps every engine identifier from Task 2's table to its `BrumleRefParams` field.
    - These are divided by 100: `buzz`, `clang`, `velsens`, `vary`, `open`, `close`, `breath`, `puff`, `air`.
    - `body` → `bodyDb` and `throat` → `throatDb`.
    - `stroke` and `curve` are choice indices in the same order.
    - The pseudo-key `"levelOnly"` sets `levelOnlyVelocity`.

- [ ] **Step 5: Bump macOS.** Make the `Package.swift` and `Info.plist` changes and the text edits listed under Files.

- [ ] **Step 6: Run the tests to verify they pass.** Run `swift test`. Expected: all pass, including the skeleton's `BrumleCoreTests`. Then run `./build.sh debug`: the app still builds.

- [ ] **Step 7: Commit.**

  ```
  git status
  git add -A
  git commit -m "chore(build): macOS 26, and the prototype as a test reference"
  ```

---

### Task 2: The parameter table, sections, modulation slots and programs

**Files:**
- Create:
  - `Sources/BrumleDSP/include/BrumleDSP.h`: the whole C interface below. Engine functions are declared now and implemented in Tasks 3–6.
  - `Sources/BrumleDSP/Params.h` and `Sources/BrumleDSP/Params.cpp`: `Param`, the table, the sections, `lfoAmountOf`, `velAmountOf`, the programs and the default kit.
  - `Sources/BrumleCore/Parameter.swift`: `Parameter`, `Parameters`, `ParameterSection` and `Programs`, as Didgeridoo's with the `brumle_` calls.
  - `Sources/BrumleCore/Modulation.swift`: `LFOs` as Didgeridoo's (`amount(of:lfo:)`, `arc`, `label(amount:)`, `snapped(amount:)`), plus `enum Velocity { static func amount(of: Parameter) -> Parameter? }`.
- Modify: `Package.swift`. Add the target `BrumleDSP` (path `Sources/BrumleDSP`), and make `BrumleCore` depend on it.
- Test: `Tests/BrumleCoreTests/ParameterTableTests.swift`

**Interfaces:** the C interface, `BrumleDSP.h`. Its comments state the thread rules, as Didgeridoo's do: setters may be called from any thread while audio runs, and `prepare`/`reset` may not run concurrently with `process`.

```c
typedef struct BrumleEngine BrumleEngine;
enum { BRUMLE_KIND_FLOAT = 0, BRUMLE_KIND_INT = 1, BRUMLE_KIND_CHOICE = 2 };
enum { BRUMLE_MODE_KEYBOARD = 0, BRUMLE_MODE_PADS = 1 };
enum { BRUMLE_KEYBOARD_SET = 0, BRUMLE_NUM_PADS = 16, BRUMLE_NUM_SETS = 17,
       BRUMLE_FIRST_PAD_NOTE = 36, BRUMLE_NUM_GROUPS = 16, BRUMLE_MAX_VOICES = 16 };
typedef struct BrumleParamInfo { const char* identifier; const char* name; const char* unit; int kind;
    float minValue, maxValue, defaultValue; int logarithmic; int numChoices; int section; } BrumleParamInfo;

int brumle_num_params(void);  void brumle_param_info(int index, BrumleParamInfo* out);
const char* brumle_param_choice(int index, int choice);
float brumle_param_to_plain(int index, float normalised);  float brumle_param_to_normalised(int index, float plain);
const char* brumle_param_display(int index, float plain, char* buffer, int bufferSize);
int brumle_num_sections(void); const char* brumle_section_name(int s); int brumle_section_size(int s); int brumle_section_param(int s, int pos);
int brumle_num_lfos(void);  int brumle_lfo_amount(int lfo, int param);  int brumle_vel_amount(int param);   // -1 = none
int brumle_num_programs(void); const char* brumle_program_name(int p); float brumle_program_value(int p, int param);
int brumle_program_sets(int param);                                  // 0 for "octave"

BrumleEngine* brumle_create(void);  void brumle_destroy(BrumleEngine*);
void brumle_prepare(BrumleEngine*, double sampleRate);  void brumle_reset(BrumleEngine*);  void brumle_request_reset(BrumleEngine*);
int  brumle_latency(const BrumleEngine*);                            // host frames the output lags the MIDI
float brumle_get_plain(const BrumleEngine*, int set, int index);      float brumle_get_normalised(const BrumleEngine*, int set, int index);
void  brumle_set_plain(BrumleEngine*, int set, int index, float plain); void brumle_set_normalised(BrumleEngine*, int set, int index, float n);
void brumle_set_program(BrumleEngine*, int set, int program);         int brumle_get_program(const BrumleEngine*, int set);
void brumle_set_mode(BrumleEngine*, int mode);                        int brumle_get_mode(const BrumleEngine*);
int  brumle_pad_note(const BrumleEngine*, int pad);   void brumle_set_pad_note(BrumleEngine*, int pad, int note);
int  brumle_pad_group(const BrumleEngine*, int pad);  void brumle_set_pad_group(BrumleEngine*, int pad, int group); // 0 = Off
int  brumle_last_note(const BrumleEngine*);           // last keyboard-mode note-on, -1 if none
void brumle_send_to_pad(BrumleEngine*, int pad);      // keyboard set + last note (36 if none) → pad; group kept
void brumle_load_default_kit(BrumleEngine*);
int  brumle_sounding_voices(const BrumleEngine*);     // voices playing and not being choked
void brumle_post_midi(BrumleEngine*, int status, int data1, int data2, int sampleOffset);
void brumle_midi(BrumleEngine*, int status, int data1, int data2, int sampleOffset);
void brumle_process(BrumleEngine*, float* left, float* right, int frames);   // right may be NULL: left gets the left channel
```

**The table.** The order is permanent. Each row is identifier, name, unit, kind, min, max, default and travel; "log" means logarithmic.

| # | Identifier | Name | Unit | Kind | Min | Max | Default | Travel |
|---|---|---|---|---|---|---|---|---|
| 0 | `ring` | Ring | s | float | 0.3 | 15 | 4 | log |
| 1 | `edge` | Edge | | float | 3 | 40 | 18 | |
| 2 | `offset` | Offset | | float | −2 | 2 | 0.2 | |
| 3 | `body` | Body | dB | float | −48 | 0 | −24 | |
| 4 | `buzz` | Buzz | % | float | 0 | 100 | 40 | |
| 5 | `clang` | Clang | % | float | 0 | 100 | 10 | |
| 6 | `velsens` | Vel Sens | % | float | 0 | 100 | 70 | |
| 7 | `stroke` | Stroke | | choice | | | Alternate | Out, In, Alternate |
| 8 | `damp` | Damp | ms | float | 2 | 80 | 10 | log |
| 9 | `keyup` | Key Up | | choice | | | Ring | Ring, Damp |
| 10 | `vary` | Vary | % | float | 0 | 100 | 20 | |
| 11 | `vowel` | Vowel | Hz | float | 500 | 3300 | 800 | log |
| 12 | `sweep` | Sweep | st | float | −24 | 24 | 14 | |
| 13 | `sweeptime` | Sweep Time | ms | float | 10 | 2000 | 160 | log |
| 14 | `curve` | Curve | | choice | | | Glide | Glide, Line, There and Back, Step |
| 15 | `reso` | Reso | | float | 4 | 40 | 15 | |
| 16 | `throat` | Throat | dB | float | −30 | 0 | −10 | |
| 17 | `throattune` | Throat Tune | Hz | float | 250 | 700 | 430 | log |
| 18 | `open` | Open | % | float | 0 | 100 | 30 | |
| 19 | `close` | Close | % | float | 0 | 100 | 0 | |
| 20 | `breath` | Breath | % | float | −100 | 100 | 30 | |
| 21 | `puff` | Puff | % | float | 0 | 100 | 30 | |
| 22 | `pufftime` | Puff Time | ms | float | 20 | 1000 | 120 | log |
| 23 | `air` | Air | % | float | 0 | 100 | 10 | |
| 24 | `volume` | Volume | dB | float | −40 | 6 | 0 | |
| 25 | `pan` | Pan | % | float | −100 | 100 | 0 | |
| 26 | `tune` | Tune | ct | float | −100 | 100 | 0 | |
| 27 | `octave` | Octave | | int | −2 | 2 | 0 | |
| 28 | `bendvowel` | Bend>Vowel | st | int | 0 | 24 | 12 | |
| 29 | `lfostart` | LFO Start | | choice | | | Hit | Hit, Free |
| 30 | `lfo1rate` | LFO 1 Rate | Hz | float | 0.02 | 20 | 6 | log |
| 31 | `lfo1shape` | LFO 1 Shape | | choice | | | Sine | Didgeridoo's 7 shapes |
| 32 | `lfo2rate` | LFO 2 Rate | Hz | float | 0.02 | 20 | 2 | log |
| 33 | `lfo2shape` | LFO 2 Shape | | choice | | | Sine | the same |

The amounts follow the knobs:

- **34–55, the LFO amounts.**
  - The order is LFO 1, then LFO 2. Each LFO covers these targets: `vowel, close, breath, open, reso, throat, buzz, body, volume, edge, offset`.
  - Identifier `lfo<n><knob>`, name `LFO <n>><Name>`, −100…100 %, default 0.
- **56–80, the VEL amounts**, for these targets: `ring, damp, edge, offset, body, buzz, clang, vary, vowel, sweep, sweeptime, reso, throat, throattune, open, close, breath, puff, pufftime, air, volume, pan, tune, lfo1rate, lfo2rate`.
  - Identifier `vel<knob>`, name `VEL><Name>`, −100…100 %, default 0.
- **81 parameters in all.**

**Sections.** Every knob is in exactly one section, in this order. The amounts are in none (section −1).

| Section | Knobs |
|---|---|
| Reed | ring, edge, offset, body, buzz, clang |
| Stroke | velsens, stroke, damp, keyup, vary |
| Mouth | vowel, sweep, sweeptime, curve, reso, throat, throattune, open, close |
| Breath | breath, puff, pufftime, air |
| Master | volume, pan, tune, octave, bendvowel, lfostart, lfo1rate, lfo1shape, lfo2rate, lfo2shape |

**Programs.** Each is an override of the defaults; the values are from `brumle_spike.cpp:363-368` in engine units.

| # | Name | Overrides |
|---|---|---|
| 0 | Brumle | none |
| 1 | Molln | ring 7.5, sweep 0, vowel 1050, reso 25, open 0, offset 0 |
| 2 | Khomus | ring 8, edge 26, buzz 70, curve 2, sweep 12, sweeptime 400 |
| 3 | Morsing | ring 1, edge 26, sweeptime 60, puff 80, close 40, damp 5 |
| 4 | Đàn Môi | clang 0, open 60, air 30, reso 10, ring 3, stroke 0 |
| 5 | Bamboo | ring 1, edge 7, clang 60, buzz 15, reso 8 |
| 6 | Genggong | ring 0.8, edge 9, clang 40, open 100 |

`Param::toPlain`, `toNormalised` and the display text are ported from Didgeridoo's `Param` (`DidgeridooEngine.cpp:139-196`). The decimals per unit:

| Unit | Decimals |
|---|---|
| s | 2 |
| Hz | 0 (2 below 10 Hz) |
| ms | 0 |
| dB | 1 |
| % | 0 |
| st | 0 |
| ct | 0 |
| Edge, Reso | 1 |
| Offset | 2 |

- [ ] **Step 1: Write the failing tests** in `ParameterTableTests.swift`.

```swift
@Test("81 parameters in the permanent order")
func order() {
    #expect(Parameters.all.count == 81)
    #expect(Parameters.all.prefix(34).map(\.identifier) == ["ring","edge","offset","body","buzz","clang","velsens","stroke","damp","keyup","vary","vowel","sweep","sweeptime","curve","reso","throat","throattune","open","close","breath","puff","pufftime","air","volume","pan","tune","octave","bendvowel","lfostart","lfo1rate","lfo1shape","lfo2rate","lfo2shape"])
    #expect(Parameters.all[34].identifier == "lfo1vowel" && Parameters.all[55].identifier == "lfo2offset")
    #expect(Parameters.all[56].identifier == "velring" && Parameters.all[80].identifier == "vellfo2rate")
    #expect(Parameters.named("velvolume")?.name == "VEL>Volume")
}
@Test("Defaults are the prototype's") func defaults() { /* each knob's defaultValue == the table above; every amount == 0 */ }
@Test("Sections hold every knob once, in the panel's order") func sections() { /* titles Reed…Master; flattened == first 34 identifiers */ }
@Test("LFO and VEL amounts point at their targets") func amounts() {
    let vowel = Parameters.named("vowel")!, stroke = Parameters.named("stroke")!
    #expect(LFOs.amount(of: vowel, lfo: 1)?.identifier == "lfo2vowel")
    #expect(Velocity.amount(of: Parameters.named("ring")!)?.identifier == "velring")
    #expect(Velocity.amount(of: stroke) == nil && LFOs.amount(of: Parameters.named("ring")!, lfo: 0) == nil)
}
@Test("Programs are the prototype's and leave Octave alone") func programs() {
    #expect(Programs.names == ["Brumle","Molln","Khomus","Morsing","Đàn Môi","Bamboo","Genggong"])
    #expect(Programs.value(program: 2, parameter: Parameters.named("curve")!) == 2)
    #expect(Programs.value(program: 4, parameter: Parameters.named("air")!) == 30)
    #expect(brumle_program_sets(Int32(Parameters.named("octave")!.index)) == 0)
}
@Test("Values round-trip and display") func display() {
    let ring = Parameters.named("ring")!
    #expect(abs(ring.plain(ring.normalised(4)) - 4) < 1e-5)
    #expect(ring.label(4) == "4.00 s")
    #expect(Parameters.named("stroke")!.label(2) == "Alternate")
}
```

- [ ] **Step 2: Run the tests to verify they fail.** Run `swift test --filter ParameterTableTests`. Expected: a build error, because `Parameters` and `brumle_*` are undefined.
- [ ] **Step 3: Implement the table.** Write `Params.h`/`Params.cpp`, the table functions of `BrumleDSP.h`, and `Parameter.swift`/`Modulation.swift`.
  - The engine functions get empty stubs in `BrumleEngine.cpp`.
  - `brumle_create` returns a zeroed engine whose `process` writes silence. Task 3 fills them in.
- [ ] **Step 4: Run the tests to verify they pass.** Run `swift test`. Expected: all pass.
- [ ] **Step 5: Commit.**

  ```
  git status
  git commit -am "feat(dsp): parameter table, sections, modulation slots and programs"
  ```

  New files must be added with `git add` first.

---

### Task 3: One voice per note — keyboard mode equals the prototype

**Files:**
- Create:
  - `Sources/BrumleDSP/Voice.h`: `Reso` and `Voice`.
  - `Sources/BrumleDSP/MidiQueue.h`: Didgeridoo's lock-free posted-MIDI queue and `MidiEvent`, from `DidgeridooEngine.cpp:471-486` and its `postMidi`/drain code.
- Modify: `Sources/BrumleDSP/BrumleEngine.cpp`: the engine struct, keyboard mode, `process` and the C functions for sets 0…16.
- Test: `Tests/BrumleCoreTests/PrototypeEquivalenceTests.swift`, `Tests/BrumleCoreTests/EngineTests.swift`

**Interfaces:**
- Consumes the Task 1 reference and scores, and the Task 2 table.
- Produces:
  - `struct KnobView { float v[kNumParams]; }`: the plain values a voice reads, in table order.
  - `Voice::start(int note, float velocity, const KnobView&, float direction, std::mt19937&, double internalRate)`
  - `Voice::process() -> StereoSample { float l, r; }`, `Voice::choke(float ms)` and `Voice::loudness()`.

**What the voice is:**
- `Voice` is the prototype's `Voice` (`brumle_spike.cpp:80-176`), ported line for line, with these substitutions only:
  - `SR` becomes the internal rate, so `Reso::set` takes it too.
  - Each `p.<field>` becomes the knob from `KnobView`, with percent knobs divided by 100.
  - The puff amount becomes `puff * (1 - velsens * (1 - velocity))`.
  - The output gain becomes `dB(volume) * velVolumeGain` (Task 4 supplies `velVolumeGain`; until then it is 1).
  - The end of `process` multiplies `y` by the pan gains: `l = y * min(1, 1 - pan)`, `r = y * min(1, 1 + pan)`, with `pan` from −1 to +1.
- The random draws in `start` stay exactly as in the prototype: four `u(rng)` in the same order, then `noise.seed(rng() | 1)`, drawn even when Vary is 0. With this, the stricter match holds with Vary and Air on as well (design §8).
- Ring, Vel Sens, Stroke, Vary, Tune and Octave are **latched at the hit**. Every other knob is re-read from the voice's `KnobView` at each control tick, and Task 4 refreshes that view for keyboard voices.
- Vary's random draws are kept per voice as factors and applied to the knob each time it is read:
  - `vowelFactor = 2^(3·vary·u/12)`, so the start vowel is `vowel * vowelFactor`;
  - `sweepFactor = 1 + 0.2·vary·u`, so the sweep time is `sweeptime * 0.001 * sweepFactor`;
  - `offsetAdd = 0.3·vary·u`, so the offset is `offset + offsetAdd`.

  Each product is computed as the prototype computes it, so fixed knobs give the prototype's numbers. The puff amount is likewise recomputed each tick from the live Puff and the latched Vel Sens.

**What the engine does:**
- **Keyboard mode.**
  - A note-on chokes every active voice with the same origin note, using that voice's own Damp, then starts a voice.
  - The direction comes from `lastDir[note]`: it starts at −1 at reset and flips on each hit with Stroke Alternate. Out is +1 and In is −1.
  - The pitch is `440 * 2^((note + 12*octave + tune/100 - 69)/12)`.
  - A note-off with Key Up = Damp chokes that note's voice.
  - CC 120 and CC 123 choke every voice.
- **The bus:**
  1. Sum the voices into L and R.
  2. Apply the DC blocker `y = x - x1 + R*y1` per channel, with `R = 1 - 48 / internalRate` (0.9995 at 96 kHz, the prototype's).
  3. Multiply by `kLevel`.
  4. Apply Didgeridoo's `limit()` (`DidgeridooEngine.cpp:1016-1022`): transparent up to 0.6, bending towards 1 above it.
  5. Flush values with `|y| < 1e-20f` to 0.
- **`kLevel`.** Set it so that the default hit (C2, velocity 127, program Brumle) peaks between −7.5 and −5 dBFS. Measure it once and write the measured number into the comment.
- **`reset`** reseeds `std::mt19937` with 12345, sets `lastDir` to −1, silences the voices and clears the bus state.
- **The rate.** In this task the voices run at the host rate; oversampling comes in Task 6.
- **Thread safety.** The 17 sets are arrays of `std::atomic<float>` (normalised). The mode, the pad notes and the groups are atomics. The audio thread reads them without locks.

- [ ] **Step 1: Write the failing tests.**

  In `PrototypeEquivalenceTests.swift`, the helper `func engineRender(_ score: Score, set: (OpaquePointer) -> Void, keyUpDamp: Bool) -> (left: [Float], right: [Float])` does the following:
  - prepares the engine at 96 kHz, resets it, sets keyboard mode and calls `set(engine)`;
  - sets Volume to −12 dB to keep the peaks under 0.6;
  - renders in blocks of 128 frames, giving each block's hits with `brumle_midi` before `brumle_process`. A hit is a note-on; a choke-only hit is a note-off.

  The comparison `func matches(_ engine: [Float], _ reference: [Float]) -> (scale: Double, residualDb: Double)` fits the scale by least squares, as `<e,r>/<r,r>`, and returns `20*log10(rms(e - scale*r) / rms(scale*r))`.

```swift
@Test("Keyboard mode plays the approved prototype scores", arguments: PrototypeEquivalenceTests.keyboardScores)
func keyboardScore(_ s: NamedScore) {
    let ref = PrototypeScores.referenceRender(s.score, params: [PrototypeScores.referenceParams(s.overrides)]) { _ in 0 }
    let out = engineRender(s.score, set: s.apply, keyUpDamp: s.keyUpDamp)
    #expect(out.left == out.right)                                   // Pan at the centre
    #expect((out.left.map(abs).max() ?? 0) < 0.6)                    // the limiter stays out of it
    let m = matches(out.left, ref)
    #expect(m.residualDb < -60, "\(s.name): residual \(m.residualDb) dB")
    #expect(abs(m.scale - Self.expectedScale) / Self.expectedScale < 1e-3)   // one output scale for all
}
```

- **`keyboardScores`.** These are the prototype's renders 01–10, 11_A, 12 and the six programs of 13.
  - They are written as `NamedScore(name:score:overrides:apply:keyUpDamp:)`.
  - The five duplicates of 01 (02_B, 03_B, 04_B, 05_A, 06_B and 07_A) are left out, with a comment saying so.
  - The overrides copy `brumle_spike.cpp:311-346` and `:363-368` into engine units.
  - A program score applies its program with `brumle_set_program(engine, 0, n)`.
  - 09_C uses `chokeAhead: 0.040` and `keyUpDamp: true`.
  - 12 (notes 36, 43, 50, 55 and 60, each 1.6 s apart) is built explicitly.
- **`expectedScale`.** It is `kLevel * dB(-12)`, written as a number after Step 3.

In `EngineTests.swift`:

```swift
@Test("The default hit at full velocity peaks around -6 dBFS") func level()      // peak in 0.42...0.56
@Test("A note re-struck chokes its own ring within Damp") func restrike()      // two hits 1 s apart, Stroke Out, Vary 0, Air 0:
    // the 1 s after the second hit equals a lone hit to -60 dB (the first ring is gone after 10 ms)
@Test("Key Up = Damp stops the note at note-off; Ring lets it ring") func keyUp()
@Test("Silence is exact 20 s after the last hit") func silenceIsExact()        // sounding voices == 0; every sample == 0
@Test("A requested reset silences at the next block") func requestedReset()
```

- [ ] **Step 2: Run the tests to verify they fail.** Run `swift test --filter "PrototypeEquivalence|Engine"`. Expected: they fail, because the engine renders silence and the residual is 0 dB.
- [ ] **Step 3: Implement** `Voice.h`, `MidiQueue.h` and the keyboard mode of `BrumleEngine.cpp` as described. Then measure `kLevel` and set `expectedScale`.
- [ ] **Step 4: Run the tests to verify they pass.**
  - Run `swift test`. Expected: all pass, with every residual under −60 dB. Note the worst residual in the commit message.
  - Run `swift test -c release --filter PrototypeEquivalence`. Expected: the same results.
- [ ] **Step 5: Commit.**

  ```
  git status
  git add Sources Tests
  git commit -m "feat(dsp): keyboard mode plays the prototype's sound (worst residual … dB)"
  ```

---

### Task 4: LFOs, velocity amounts, live knobs and wheels

**Files:**
- Create: `Sources/BrumleDSP/Lfo.h`, Didgeridoo's seven shapes from `turnLfos` (`DidgeridooEngine.cpp:724-748`) for one LFO with its own phase and its own `Xorshift32` (Didgeridoo `dsp/noise.h`, copied with its MIT header).
- Modify: `Sources/BrumleDSP/Voice.h`, `Sources/BrumleDSP/BrumleEngine.cpp`
- Test: `Tests/BrumleCoreTests/ModulationTests.swift`, and the 11_B score added to `PrototypeEquivalenceTests.keyboardScores`.

**Interfaces:**
- Consumes `KnobView` and `Voice` from Task 3.
- Produces `void Engine::viewFor(const Voice&, KnobView&)`, which computes a voice's current knob values. This is the one place that adds the modulation:
  - `position = knob + Σ_lfo amount_lfo * lfoValue_lfo − velAmount * (1 − velocity)`, in normalised units of the knob's travel, clamped to 0…1, then converted to plain.
  - The exception is Volume: its VEL amount is applied as a gain `max(0, 1 − velAmount * (1 − velocity))`, and is not a position offset.

**The rules:**
- **Each voice owns two LFOs.**
  - With LFO Start = Hit, a hit sets the LFO phase to 0 and reseeds the voice's generator with a fixed seed (`0x9E3779B9 + lfo`), so every hit repeats exactly.
  - With Free, the voice copies the phase and generator of the engine's free-running LFOs, which advance every control tick.
  - The LFOs step at the voice's control tick, `rate * 16 / internalRate` per tick.
- **Keyboard voices** refresh their `KnobView` from set 0 at every control tick. Pad voices take theirs once, at the hit (Task 5).
- **Wheels** act on keyboard voices only:
  - Pitch bend multiplies the Vowel frequency by `2^(bend * bendvowel / 12)`, with `bend` from −1 to +1.
  - The mod wheel adds `cc1 / 127` to Close's position.
  - Channel aftertouch adds `0.5 * pressure / 127` to Breath's position, so full pressure adds +100 %.

- [ ] **Step 1: Write the failing tests** in `ModulationTests.swift`. Every render uses Vary 0, Air 0 and Stroke Out unless the test says otherwise.

```swift
@Test("A VEL amount moves a soft hit exactly as far as turning the knob down would")
func velMatchesKnob() {   // knob Vowel at n0, VEL>Vowel +60 %, velocity 64
    // == render with Vowel at n0 - 0.6 * (1 - 64/127), VEL 0, velocity 64; residual < -100 dB
}
@Test("A full-velocity hit ignores its VEL amounts") func velAtFull()   // VEL>Ring +100, velocity 127 == VEL 0
@Test("VEL>Volume scales the level") func velVolume()        // Vel Sens 0, VEL>Volume 100, velocity 64 == (64/127) * the velocity-127 render
@Test("With LFO Start = Hit every hit repeats exactly") func lfoHitRepeats()   // LFO1>Vowel 40, rate 3 Hz; two hits 2 s apart:
    // the first 1 s of each are bit-identical
@Test("With LFO Start = Free hits differ") func lfoFree()
@Test("An LFO amount moves the sound; amount 0 leaves it alone") func lfoAmount()
@Test("A keyboard voice follows the knobs while it rings") func liveKnobs()     // Close → 100 % 0.5 s into a hit: the RMS of the next 0.5 s drops by > 6 dB
@Test("Pitch bend moves the vowel up") func bendMovesVowel()  // Sweep 0: the spectral centroid of 0.2–1.0 s rises with bend +1
@Test("The mod wheel closes the mouth and aftertouch adds breath") func wheels()
```

In `PrototypeEquivalenceTests`, add 11_B, the "level only" run of the 8 hits in `brumle_spike.cpp:348-354`. Task 3 already has 11_A.
- The engine side of 11_B is Vel Sens 0 with VEL>Volume 100.
- The reference side is `levelOnly`.

- [ ] **Step 2: Run the tests to verify they fail.** Run `swift test --filter "Modulation|PrototypeEquivalence"`. Expected: the VEL, LFO and wheel tests fail, because the amounts have no effect yet.
- [ ] **Step 3: Implement** `Lfo.h`, `viewFor`, the per-tick refresh, the latching (Ring, Vel Sens, Stroke, Vary, Tune and Octave at the hit), and the wheels.
- [ ] **Step 4: Run the tests to verify they pass.** Run `swift test`. Expected: all pass, and Task 3's equivalence tests still pass.
- [ ] **Step 5: Commit.**

  ```
  git status
  git add Sources Tests
  git commit -m "feat(dsp): LFOs, velocity amounts, live knobs and wheels"
  ```

---

### Task 5: Pad mode — sets, pitches, mute groups, Send to pad and the default kit

**Files:**
- Modify: `Sources/BrumleDSP/BrumleEngine.cpp`, `Sources/BrumleDSP/Params.cpp` (the default kit)
- Test: `Tests/BrumleCoreTests/PadTests.swift`, and score 14 added to `PrototypeEquivalenceTests`.

**Interfaces:**
- Consumes `viewFor`, `Voice` and the C API.
- Produces:
  - `struct Origin { int kind; int note; int pad; int group; }`, where kind is `kOriginKey` or `kOriginPad`.
  - The choke and alternation rules below.
  - `kDefaultKit[16]`, entries of `{ program, note, group, overrides }`.

**The rules** (design §7):
- **Pad mode** plays notes 36–51 as pads 0–15.
  - The pitch is the pad's note plus the pad set's Octave and Tune.
  - The voice copies its pad set into its `KnobView` once, at the hit, and never re-reads it. Wheels do not touch it.
- **A pad hit chokes:**
  - every voice of the same pad;
  - if the pad's group is not Off, every pad voice of the same group.
- **Stroke Alternate** keeps `lastDir` per group, or per pad when the group is Off. Indices are 0–15 for groups 1–16 and 16–31 for pads with no group. Each starts at −1 at reset.
- **`brumle_send_to_pad`** copies set 0 into the pad's set. The pad's note becomes `brumle_last_note`, or 36 if no note has been played. The pad's group is kept.
- **`brumle_set_mode`** does not stop ringing voices.
- **The default kit** is a call, to be approved by ear in Task 8. `brumle_create` and `brumle_reset` do not reload it; only `brumle_create` and `brumle_load_default_kit` do.

  | Pad | Note | Program | Group | Overrides |
  |---|---|---|---|---|
  | 1 | 36 | Brumle | 1 | none |
  | 2 | 36 | Brumle | 1 | ring 0.6 |
  | 3 | 39 | Bamboo | Off | none |
  | 4 | 43 | Molln | 2 | none |
  | 5 | 48 | Morsing | 3 | none |
  | 6 | 38 | Khomus | 4 | none |
  | 7 | 39 | Đàn Môi | Off | none |
  | 8 | 41 | Genggong | Off | none |

  Pads 9–16 repeat pads 1–8 seven semitones higher. Groups 1–4 become 5–8, and Off stays Off.

- [ ] **Step 1: Write the failing tests** in `PadTests.swift`. They use Vary 0, Air 0 and Stroke Out unless stated.

```swift
@Test("A pad hit is a frozen key press")      // Send to pad after playing note 43; pad hit == keyboard note 43, residual < -100 dB
@Test("Pads ignore later knob changes; keyboard voices follow them") // Close → 100 during a pad's ring: pad output unchanged
@Test("Pad mode ignores notes outside 36–51") func padModeIgnoresOtherNotes()  // notes 35 and 52: silence
@Test("Same-pitch pads with Group Off ring over each other")   // pads 1, 2 both note 36: second hit 0.5 s later; output == sum of the lone hits
@Test("A hit chokes the other pads of its group")              // same, both in group 1: first ring gone 20 ms after the second hit
@Test("Stroke Alternate alternates across a group")            // Stroke Alternate, pads 1, 2 equal, group 1: hit 1 then 2 == hit 1 then 1;
                                                               // with Group Off: hit 1 then 2 != hit 1 then 1
@Test("A velocity-0 note-on is a note-off")                    // Key Up Damp: note-on vel 0 chokes like 0x80
@Test("Send to pad copies the set and the last note, and keeps the group")
@Test("The default kit is loaded at creation")                 // pad notes, groups and programs as in the table
@Test("Mode switch leaves ringing voices alone")
@Test("Wheels change keyboard voices, not ringing pad voices") func wheelsLeavePadsAlone()
```

In `PrototypeEquivalenceTests`, add score 14, the overlapping kit from `brumle_spike.cpp:376-388`.
- The engine plays it in pad mode, on pads 0–3 with groups Off:
  - pad 0: Brumle at note 36;
  - pad 1: Molln at 43;
  - pad 2: Morsing at 48;
  - pad 3: Bamboo at 39.
- The engine receives notes 36–39, and the reference receives the pitches 36, 43, 48 and 39, each with its own parameter set.
- The residual must be under −60 dB.

- [ ] **Step 2: Run the tests to verify they fail.** Run `swift test --filter "Pad|PrototypeEquivalence"`. Expected: they fail, because pad mode is not implemented.
- [ ] **Step 3: Implement** the origins, the choke and alternation rules, the pad state, `send_to_pad` and the default kit.
- [ ] **Step 4: Run the tests to verify they pass.** Run `swift test`. Expected: all pass.
- [ ] **Step 5: Commit.**

  ```
  git status
  git add Sources Tests
  git commit -m "feat(dsp): pad mode with mute groups, Send to pad and a default kit"
  ```

---

### Task 6: The voice pool, 2× oversampling and sample rates

**Files:**
- Create: `Sources/BrumleDSP/HalfBand.h`, a linear-phase FIR half-band decimator by 2.
  - The taps are designed in `prepare` (windowed sinc, Kaiser window) into a fixed-size array.
  - The stopband is at least 90 dB above 0.55 × the host's Nyquist. The tap count is fixed by that, at most 63.
- Modify: `Sources/BrumleDSP/BrumleEngine.cpp`
- Test: `Tests/BrumleCoreTests/EngineTests.swift`

**Interfaces:**
- Produces `brumle_latency()`: the decimator's group delay in host frames when oversampling, otherwise 0.
- **Stealing.**
  - There are 20 voice slots, and at most 16 voices sound at once.
  - When a 17th hit comes, the sounding voice with the lowest `loudness()` (`swing * exp(-t/tau) * chokeGain * outGain`) is choked with a 3 ms damp.
  - The new voice takes a free slot, or else the quietest choking slot.
- **Oversampling.**
  - Below 88.2 kHz the internal rate is twice the host rate, otherwise it equals it.
  - MIDI offsets are doubled.
  - The bus runs at the internal rate, and the limiter runs after decimation.

- [ ] **Step 1: Write the failing tests** in `EngineTests.swift`.

```swift
@Test("At 48 kHz the bright high note aliases no more than at 96 kHz")   // note 84, Edge 40, Vary 0, Air 0, Breath 0, Puff 0:
    // DFT power below 20 kHz in bins farther than 20 Hz from any k*f0, re the total: (48 kHz) <= (96 kHz) + 3 dB
@Test("The pitch is right at every rate", arguments: [44_100.0, 48_000, 88_200, 96_000, 192_000])
    // Molln (Sweep 0) on note 57: fundamental by zero-crossing autocorrelation within 0.1 % of 220 Hz
@Test("Latency is the decimator's delay") // 44.1/48 kHz: > 0 and a click at frame 0 peaks at frame == latency (±1); 96 kHz: 0
@Test("Re-preparing changes the rate cleanly") func rePrepareChangesRate()   // 96k → 44.1k → 96k: pitch test passes each time; first block after prepare is finite
@Test("Extreme knobs stay finite") func extremeKnobsStayFinite()             // all knobs min, all max, the Reso/Vowel/Sweep case on note 96, at 44.1 and 96 kHz
@Test("A flood of hits stays within 16 voices") func stealingStaysBounded()  // see Review Focus 3; brumle_sounding_voices <= 16 after every block
```

- [ ] **Step 2: Run the tests to verify they fail.** Run `swift test --filter Engine`. Expected: the aliasing, latency and stealing tests fail.
- [ ] **Step 3: Implement** `HalfBand.h`, the internal rate, stealing and latency.
- [ ] **Step 4: Run the tests to verify they pass.** Run `swift test`. Expected: all pass, and the 96 kHz equivalence tests are unchanged, because no oversampling runs at that rate.
- [ ] **Step 5: Commit.**

  ```
  git status
  git add Sources Tests
  git commit -m "feat(dsp): voice stealing and 2x oversampling below 88.2 kHz"
  ```

---

### Task 7: The Swift wrapper, thread safety and the sound's regression references

**Files:**
- Create:
  - `Sources/BrumleCore/Synth.swift`
  - `Tests/BrumleCoreTests/SynthTests.swift`
  - `Tests/BrumleCoreTests/ThreadTests.swift`
  - `Tests/BrumleCoreTests/SoundRegressionTests.swift`

**Interfaces.** `Synth` mirrors Didgeridoo's `Synth.swift`, with sets and pads. The wrapper only forwards to the engine.

```swift
public enum PlayMode: Int, Sendable { case keyboard = 0, pads = 1 }
public enum SoundSet: Hashable, Sendable { case keyboard; case pad(Int) /* 0...15 */; var index: Int32 }
public final class Synth: @unchecked Sendable {
    public init(sampleRate: Double = 44_100); public func prepare(sampleRate: Double); public var latency: Int { get }
    public func value(of: Parameter, in: SoundSet = .keyboard) -> Float;  public func setValue(_: Float, of: Parameter, in: SoundSet = .keyboard)
    public func normalisedValue(of: Parameter, in: SoundSet = .keyboard) -> Float; public func setNormalisedValue(_: Float, of: Parameter, in: SoundSet = .keyboard)
    public func program(in: SoundSet = .keyboard) -> Int;  public func loadProgram(_: Int, into: SoundSet = .keyboard)
    public var mode: PlayMode { get set }
    public func padNote(_ pad: Int) -> Int;  public func setPadNote(_ note: Int, pad: Int)
    public func padGroup(_ pad: Int) -> Int?;  public func setPadGroup(_ group: Int?, pad: Int)   // nil = Off
    public var lastNote: Int? { get };  public func sendToPad(_ pad: Int);  public func loadDefaultKit()
    public var soundingVoices: Int { get }
    public func postMIDI(status: UInt8, data1: UInt8, data2: UInt8); public func noteOn(_: Int, velocity: Int = 100); public func noteOff(_: Int)
    public func allNotesOff(); public func releaseAll()
    public func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?, frames: Int)
}
```

- [ ] **Step 1: Write the failing tests.**
  - **`SynthTests`:**
    - each property round-trips through the engine;
    - `setPadGroup(nil)` reads back nil;
    - `noteOn(200)` clamps to 127 and `velocity: 0` sounds as velocity 1, as in Didgeridoo;
    - `sendToPad` copies `lastNote`.
  - **`ThreadTests`:** one thread renders 4 s at 48 kHz in blocks of 128 frames. Another thread at the same time:
    - sets random parameters on random sets;
    - loads programs;
    - switches the mode;
    - sets pad notes and groups;
    - sends to pads;
    - posts note-ons and note-offs.

    The test expects every sample to be finite. It must run clean under `swift test --sanitize=thread`.
  - **`SoundRegressionTests`:** written as Didgeridoo's, with an FNV-1a fingerprint and the RMS of each second.
    - Rates: 44 100, 48 000 and 96 000 Hz.
    - Scores:
      1. the default phrase;
      2. a damped phrase (09_C);
      3. Stroke In and Stroke Out;
      4. the default-kit groove: Task 8's listening groove, pads 1–8, 4 bars at 100 BPM;
      5. two same-pitch pads with Group Off, then in one group;
      6. an LFO and VEL phrase: LFO1>Vowel 40 and VEL>Ring 50 over the 16th-note accents.
    - At first `references` is empty, and the test fails, printing each line.
- [ ] **Step 2: Run the tests to verify they fail.** Run `swift test --filter "Synth|Thread|SoundRegression"`. Expected: a build error (no `Synth`), then the regression test fails with the printed reference lines.
- [ ] **Step 3: Implement `Synth.swift`.** Run the regression suite in debug and in release. The fingerprints must be identical; if they differ, find the fused or reordered operation before going on. Paste the printed lines into `references`, with a comment giving the date and the phase.
- [ ] **Step 4: Run the tests to verify they pass.**
  - Run `swift test`. Expected: all pass.
  - Run `swift test --sanitize=thread`. Expected: all pass, with no TSan reports.
  - Run `swift test -c release`. Expected: all pass.
- [ ] **Step 5: Commit.**

  ```
  git status
  git add Sources Tests
  git commit -m "feat(core): Synth wrapper, thread test and sound regression references"
  ```

---

### Task 8: Listening, verification and closing the phase

**Files:**
- Create:
  - `Tests/BrumleCoreTests/ListeningRenders.swift`
  - `.planning/phases/02-engine/VERIFICATION.md`
- Modify:
  - `CHANGELOG.md`
  - `.planning/ROADMAP.md`: the 02-engine row ✅; 03-panel-design is next.
  - `.planning/STATE.md`
  - `.planning/specs/2026-11-15-engine-design.md`: the status line becomes "approved 2026-11-15; phase 02 built".

**`ListeningRenders.swift`:**
- A test that is skipped unless `BRUMLE_LISTEN_DIR` is set (`.enabled(if: ProcessInfo.processInfo.environment["BRUMLE_LISTEN_DIR"] != nil)`).
- It writes 24-bit 48 kHz stereo WAVs from the engine. This exercises the oversampled path at a common host rate.
- The design says each feature is heard in the phase that adds it. The renders are:
  1. `01_default_kit_groove`: pads 1–8, 4 bars at 100 BPM, the pattern of the prototype's `14_pads_overlapping_kit` extended to pads 5–8.
  2. `02_curve_step`
  3. `03_keyup_damp`
  4. `04_close_by_modwheel`
  5. `05_lfo1_vowel_3Hz`
  6. `06_pan_across_pads`
  7. `07_pitchbend_vowel`
  8. `08_aftertouch_breath`
  9. `09_vel_ring_and_vowel`: the same accents with VEL>Ring 60 and VEL>Vowel 40.
  10. `10_default_hit_44k1_vs_96k`: one file at each rate.

- [ ] **Step 1: Write the listening renders.** Run:

  ```
  BRUMLE_LISTEN_DIR=<scratchpad>/listen swift test --filter ListeningRenders
  ```

  Expected: 11 WAV files. Check each one's peak, which must be ≤ −0.5 dBFS.
- [ ] **Step 2: Have the author listen.** Hand the files over with one line per file saying what to listen for.
  - The default kit, Curve Step, Key Up Damp, Close, the LFOs, Pan, the wheels and VEL are checked by ear (design §6).
  - Fix what the author rejects, then render and listen again. If a fix changes the sound, update the regression references with a CHANGELOG note.
- [ ] **Step 3: Run the whole verification and record the output in `VERIFICATION.md`.**
  - `swift test`
  - `swift test -c release`
  - `swift test --sanitize=thread`
  - `./build.sh debug`
  - `./build.sh release`
  - Launch the app at `build/release/Brumle.app` by its path. It still shows the skeleton window on macOS 26.
  - Record the worst equivalence residual, `kLevel`, the latency at 44.1 and 48 kHz, and the author's verdicts per render.
- [ ] **Step 4: Update the records.**
  - Add one line to `CHANGELOG.md`: "Sound engine: a synthesized jaw harp with keyboard and pad modes (not playable yet: the app and the Audio Unit come next)."
  - Update ROADMAP and STATE, and the design doc's status line.
- [ ] **Step 5: Commit and merge.**

  ```
  git status
  git add -A
  git commit -m "docs(planning): phase 02 verified"
  ```

  Then switch to `main`, merge `feature/02-engine` with `--no-ff`, and run `swift test` on `main`. **Ask the author before any push.**
