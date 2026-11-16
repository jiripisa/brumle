// BrumleDSP.h - C interface to the Brumle sound engine.
//
// One engine = one jaw harp: sixteen voices that share the players' hands (the keyboard) or
// the sixteen pads of a kit. The Audio Unit (C++) and the standalone app (Swift, through
// BrumleCore) both drive it through these functions.
//
// Threads:
//   * brumle_process() and brumle_midi() belong to the audio thread.
//   * brumle_post_midi(), the parameter setters/getters, brumle_set_program(), the mode and
//     pad calls and brumle_request_reset() may be called from any thread while audio runs,
//     the audio thread included: none of them locks or allocates.
//   * brumle_prepare() and brumle_reset() must not run concurrently with brumle_process().
//
// Parameter values come in two forms: "plain" (the real value: s, Hz, dB, %, an index) and
// "normalised" (0..1, what a knob position is). The engine stores normalised values.
//
// Sets: the sound is a set of knobs (the parameters below). The keyboard has one set; each of
// the 16 pads has a set of its own, so that every pad can sound different. A set is addressed by
// an index: BRUMLE_KEYBOARD_SET (0), or 1...16 for a pad.

#ifndef BRUMLE_DSP_H
#define BRUMLE_DSP_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct BrumleEngine BrumleEngine;

enum { BRUMLE_KIND_FLOAT = 0, BRUMLE_KIND_INT = 1, BRUMLE_KIND_CHOICE = 2 };
enum { BRUMLE_MODE_KEYBOARD = 0, BRUMLE_MODE_PADS = 1 };
enum { BRUMLE_KEYBOARD_SET = 0, BRUMLE_NUM_PADS = 16, BRUMLE_NUM_SETS = 17,
       BRUMLE_FIRST_PAD_NOTE = 36, BRUMLE_NUM_GROUPS = 16, BRUMLE_MAX_VOICES = 16 };

typedef struct BrumleParamInfo
{
    const char* identifier;   // stable name used in saved state; never changes
    const char* name;         // shown to the user
    const char* unit;         // "s", "Hz", "ms", "dB", "%", "st", "ct" or ""
    int   kind;               // BRUMLE_KIND_*
    float minValue, maxValue, defaultValue;   // plain values
    int   logarithmic;        // 1 = the knob travels logarithmically (times, frequencies)
    int   numChoices;         // > 0 only for BRUMLE_KIND_CHOICE
    int   section;            // the section it is shown in (see brumle_num_sections), -1 if none
} BrumleParamInfo;

// ----- parameter, section and program tables (the same for every engine) --------------------
int         brumle_num_params(void);
void        brumle_param_info(int index, BrumleParamInfo* out);
const char* brumle_param_choice(int index, int choice);
float       brumle_param_to_plain(int index, float normalised);
float       brumle_param_to_normalised(int index, float plain);
// Text for a plain value, without the unit ("4.00", "-24.0", "Alternate", "+1"). Returns buffer.
const char* brumle_param_display(int index, float plain, char* buffer, int bufferSize);

// The sections the knobs are shown in ("Reed", "Stroke", "Mouth", "Breath", "Master") and the
// knobs of each in the order they are shown: the app's panels and the Audio Unit's parameter
// groups. The amounts below are in no section.
int         brumle_num_sections(void);
const char* brumle_section_name(int s);
int         brumle_section_size(int s);
int         brumle_section_param(int s, int pos);   // a parameter index, -1 if none

// The modulation slots. Each of the two LFOs has an amount on every knob it can move, and the
// hit's velocity has one on every knob it can move: parameters of their own, shown in no
// section. The call gives the amount's index, or -1 for a knob that cannot be moved so.
int         brumle_num_lfos(void);
int         brumle_lfo_amount(int lfo, int param);
int         brumle_vel_amount(int param);

int         brumle_num_programs(void);
const char* brumle_program_name(int p);
float       brumle_program_value(int p, int param);   // plain
int         brumle_program_sets(int param);           // 0 for "octave", which programs leave alone

// ----- one engine ---------------------------------------------------------------------------
BrumleEngine* brumle_create(void);
void          brumle_destroy(BrumleEngine*);
// Sets the host sample rate and then resets the engine as brumle_reset() does. A rate that is not
// positive and finite is ignored, and nothing is reset.
void          brumle_prepare(BrumleEngine*, double sampleRate);
// Silences every voice, puts the wheels at rest and forgets the last note. The knob sets, the
// pads (notes, groups) and the mode stay as they are.
void          brumle_reset(BrumleEngine*);
// The same reset, done by the audio thread at the start of its next brumle_process() call.
void          brumle_request_reset(BrumleEngine*);
// Host frames the output lags the MIDI: the decimator's delay below 88.2 kHz, where the voices run
// at twice the rate, and 0 from 88.2 kHz up.
int           brumle_latency(const BrumleEngine*);

float brumle_get_plain(const BrumleEngine*, int set, int index);
float brumle_get_normalised(const BrumleEngine*, int set, int index);
void  brumle_set_plain(BrumleEngine*, int set, int index, float plain);
void  brumle_set_normalised(BrumleEngine*, int set, int index, float n);

// Loads a built-in program into a set: every parameter but "octave" is overwritten. The octave
// belongs to the player's hands, not to the sound.
void  brumle_set_program(BrumleEngine*, int set, int program);
int   brumle_get_program(const BrumleEngine*, int set);
// Records which program a set last loaded without loading it: no knob changes. For restoring saved
// state whose knob values come from elsewhere. A bad set or program is ignored.
void  brumle_set_program_index(BrumleEngine*, int set, int program);

// The mode: the keyboard plays the keyboard set at the pitch of each key; the pads play their
// own sets at the pitch of each pad, hit by notes 36-51 (other notes are ignored). A voice
// already ringing when the mode changes rings on as it was.
void  brumle_set_mode(BrumleEngine*, int mode);
int   brumle_get_mode(const BrumleEngine*);

// Pads: each has a pitch (a MIDI note) and a mute group. A hit on a pad chokes its own pad's
// sounding voices and those of every pad in its group (0 = Off: no group). Like the pitch, the
// group belongs to the pad, not to its set. A pad's voice copies the pad's set at the hit and
// does not follow later changes to it, nor the wheels.
int   brumle_pad_note(const BrumleEngine*, int pad);
void  brumle_set_pad_note(BrumleEngine*, int pad, int note);
int   brumle_pad_group(const BrumleEngine*, int pad);
void  brumle_set_pad_group(BrumleEngine*, int pad, int group);   // 0 = Off
// How many times a pad has been hit since the engine was created: the panel flashes a pad when it
// changes. Counted on the audio thread; a reset leaves it alone. 0 for a bad pad.
int   brumle_pad_hits(const BrumleEngine*, int pad);
int   brumle_last_note(const BrumleEngine*);          // last keyboard-mode note-on since the last reset, -1 if none
// Copies the keyboard set (and its program) and the pitch of the last note (36 if none) to a
// pad; its group is kept. The copy goes value by value with relaxed atomics, not as a whole: a pad
// hit landing mid-copy freezes a mix of old and new values for that one hit.
void  brumle_send_to_pad(BrumleEngine*, int pad);
// A kit built from the programs at various pitches, so that pad mode sounds at once: what the
// pads hold when the engine is created. Overwrites every pad's set, note and group, value by value
// with relaxed atomics like brumle_send_to_pad: a pad hit landing mid-load freezes a mix of old and
// new values for that one hit.
void  brumle_load_default_kit(BrumleEngine*);
int   brumle_sounding_voices(const BrumleEngine*);    // voices playing and not being choked

// MIDI from any thread; played in the next brumle_process() call, sampleOffset frames into it
// (0 = at its start).
void  brumle_post_midi(BrumleEngine*, int status, int data1, int data2, int sampleOffset);
// MIDI from the audio thread with a sample offset into the next brumle_process() call.
void  brumle_midi(BrumleEngine*, int status, int data1, int data2, int sampleOffset);
// One brumle_process() call plays at most 256 events. Those from brumle_midi() take that room
// first, and any beyond it are dropped. Posted events beyond it stay queued and play in the next
// call, in the order posted, at their sample offset into that call. The queue holds 512 posted
// events; an event posted while it is full is dropped.

// MIDI controllers on the keyboard set's knobs. Every knob comes with a controller (a control
// change number) and can be given another; a control change on any channel then puts the knob
// of the keyboard set where its value says: 0 the bottom of its travel, 127 the top, and 64 the
// middle of a knob that has one (-100 ... 100 %). A choice takes the choice nearest to the value.
// The pads' sets are never moved, not in pad mode either. A controller serves one knob, and the
// amounts have none. The control change is applied at its sample offset, in the order of the
// block's MIDI. Controllers 1 (the mod wheel), 120, 121 and 123 keep their meanings. All of these
// may be called from any thread while audio runs.
int  brumle_standard_controller(int param);               // what a knob comes with; -1 for none
int  brumle_controller_reserved(int cc);                  // 1 for one MIDI or the engine keeps for itself
int  brumle_get_controller(const BrumleEngine*, int param);          // -1 for none
// -1 takes the knob's controller away. A reserved controller is not taken; one another knob has
// moves to this one.
void brumle_set_controller(BrumleEngine*, int param, int cc);
void brumle_reset_controllers(BrumleEngine*);             // every knob back to its standard controller
// Learn: the knob takes the next controller that moves, not a reserved one, and goes where it
// says. -1 (or a parameter that is not a knob) calls it off.
void brumle_learn(BrumleEngine*, int param);
int  brumle_learning(const BrumleEngine*);               // the knob that is learning, -1 for none
// Counts what MIDI changed without the caller: a knob moved by its controller, a controller
// learnt. A window compares it with what it saw last to know when to read the engine again: the
// count is raised after the change (release) and read with acquire, so a window that sees it rise
// reads the new values.
unsigned brumle_changes(const BrumleEngine*);

// Renders `frames` samples. `right` may be NULL: left then gets the left channel.
void  brumle_process(BrumleEngine*, float* left, float* right, int frames);

#ifdef __cplusplus
}
#endif

#endif // BRUMLE_DSP_H
