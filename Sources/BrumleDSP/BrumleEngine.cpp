// BrumleEngine.cpp - the Brumle sound engine and its C interface.
//
// The table functions of the C interface are complete. The engine itself is still a stub: it
// writes silence and keeps no state. The following tasks of the phase fill it in.

// A product and a sum stay two operations. Fused into one they round once instead of twice, and
// an optimised build fuses where an unoptimised one does not: without this line two programs
// rendered samples that differed in their last bit between a debug and a release build, and the
// sound's references could hold for one of them only.
#pragma clang fp contract(off)

#include "BrumleDSP.h"
#include "Params.h"

#include <cstdio>
#include <cstring>

using namespace brumle;

// The engine: a stub until Task 3.
struct BrumleEngine { int mode = BRUMLE_MODE_KEYBOARD; };

// ---------------------------------------------------------------------------------------------
// C interface: the tables
// ---------------------------------------------------------------------------------------------
int brumle_num_params(void) { return kNumParams; }

void brumle_param_info(int index, BrumleParamInfo* out)
{
    if (!out || !validParam(index)) return;
    const Param& p = param(index);
    out->identifier = p.id; out->name = p.name; out->unit = p.unit; out->kind = p.kind;
    out->minValue = p.min; out->maxValue = p.max; out->defaultValue = p.def;
    out->logarithmic = p.logarithmic ? 1 : 0;
    out->numChoices = p.kind == BRUMLE_KIND_CHOICE ? (int)p.max + 1 : 0;
    out->section = sectionOf(index);
}

const char* brumle_param_choice(int index, int choice) { return validParam(index) ? choiceName(index, choice) : ""; }

float brumle_param_to_plain(int index, float normalised) { return validParam(index) ? param(index).toPlain(normalised) : 0.0f; }
float brumle_param_to_normalised(int index, float plain) { return validParam(index) ? param(index).toNormalised(plain) : 0.0f; }

const char* brumle_param_display(int index, float plain, char* buffer, int bufferSize)
{
    if (!buffer || bufferSize <= 0) return "";
    buffer[0] = 0;
    if (!validParam(index)) return buffer;
    const Param& p = param(index);
    if (index == kOctave && plain >= 0.5f) std::snprintf(buffer, (size_t)bufferSize, "+%d", (int)std::lround(plain));
    else if (p.kind == BRUMLE_KIND_CHOICE) std::snprintf(buffer, (size_t)bufferSize, "%s", choiceName(index, (int)std::lround(plain)));
    else if (p.kind == BRUMLE_KIND_INT) std::snprintf(buffer, (size_t)bufferSize, "%d", (int)std::lround(plain));
    else
    {
        // A frequency has two decimals only where it is small: "6.00 Hz", "800 Hz".
        const int decimals = p.decimals >= 0 ? p.decimals : (std::fabs(plain) < 10.0f ? 2 : 0);
        std::snprintf(buffer, (size_t)bufferSize, "%.*f", decimals, (double)plain);
        if (buffer[0] == '-')     // turn "-0.0" into "0.0"
        {
            bool allZero = true;
            for (const char* q = buffer + 1; *q; ++q) if (*q != '0' && *q != '.') { allZero = false; break; }
            if (allZero) std::memmove(buffer, buffer + 1, std::strlen(buffer));
        }
    }
    return buffer;
}

static bool validSection(int s) { return s >= 0 && s < (int)sections().size(); }

int brumle_num_sections(void) { return (int)sections().size(); }
const char* brumle_section_name(int s) { return validSection(s) ? sections()[(size_t)s].name : ""; }
int brumle_section_size(int s) { return validSection(s) ? (int)sections()[(size_t)s].params.size() : 0; }
int brumle_section_param(int s, int pos)
{
    return pos >= 0 && pos < brumle_section_size(s) ? sections()[(size_t)s].params[(size_t)pos] : -1;
}

int brumle_num_lfos(void) { return kNumLfos; }
int brumle_lfo_amount(int lfo, int param) { return lfo >= 0 && lfo < kNumLfos && validParam(param) ? amountOf(lfo, param) : -1; }
int brumle_vel_amount(int param) { return validParam(param) ? velAmountOf(param) : -1; }

int brumle_num_programs(void) { return (int)programs().size(); }
const char* brumle_program_name(int p) { return p >= 0 && p < brumle_num_programs() ? programs()[(size_t)p].name : ""; }
int brumle_program_sets(int param) { return validParam(param) && programSets(param) ? 1 : 0; }
float brumle_program_value(int p, int param)
{
    return p >= 0 && p < brumle_num_programs() && validParam(param) ? programs()[(size_t)p].values[param] : 0.0f;
}

// ---------------------------------------------------------------------------------------------
// C interface: the engine (stubs until Tasks 3-6)
// ---------------------------------------------------------------------------------------------
BrumleEngine* brumle_create(void) { return new BrumleEngine(); }
void brumle_destroy(BrumleEngine* e) { delete e; }
void brumle_prepare(BrumleEngine*, double) {}
void brumle_reset(BrumleEngine*) {}
void brumle_request_reset(BrumleEngine*) {}
int  brumle_latency(const BrumleEngine*) { return 0; }

float brumle_get_plain(const BrumleEngine*, int, int index) { return validParam(index) ? param(index).def : 0.0f; }
float brumle_get_normalised(const BrumleEngine*, int, int index) { return validParam(index) ? param(index).toNormalised(param(index).def) : 0.0f; }
void  brumle_set_plain(BrumleEngine*, int, int, float) {}
void  brumle_set_normalised(BrumleEngine*, int, int, float) {}
void  brumle_set_program(BrumleEngine*, int, int) {}
int   brumle_get_program(const BrumleEngine*, int) { return 0; }
void  brumle_set_mode(BrumleEngine* e, int mode) { e->mode = mode; }
int   brumle_get_mode(const BrumleEngine* e) { return e->mode; }

int   brumle_pad_note(const BrumleEngine*, int) { return BRUMLE_FIRST_PAD_NOTE; }
void  brumle_set_pad_note(BrumleEngine*, int, int) {}
int   brumle_pad_group(const BrumleEngine*, int) { return 0; }
void  brumle_set_pad_group(BrumleEngine*, int, int) {}
int   brumle_last_note(const BrumleEngine*) { return -1; }
void  brumle_send_to_pad(BrumleEngine*, int) {}
void  brumle_load_default_kit(BrumleEngine*) {}
int   brumle_sounding_voices(const BrumleEngine*) { return 0; }

void  brumle_post_midi(BrumleEngine*, int, int, int, int) {}
void  brumle_midi(BrumleEngine*, int, int, int, int) {}

void brumle_process(BrumleEngine*, float* left, float* right, int frames)
{
    if (left && frames > 0) std::memset(left, 0, sizeof(float) * (size_t)frames);
    if (right && frames > 0) std::memset(right, 0, sizeof(float) * (size_t)frames);
}
