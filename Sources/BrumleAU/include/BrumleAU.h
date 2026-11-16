// BrumleAU.h - identity of the Brumle Audio Unit.
//
// These four-character codes are permanent: hosts find the plug-in and its saved state by them.
// They must match the AudioComponents entry in Resources/AudioUnit-Info.plist.

#ifndef BRUMLE_AU_H
#define BRUMLE_AU_H

#define BRUMLE_AU_TYPE          'aumu'   // music device (instrument)
#define BRUMLE_AU_SUBTYPE       'Brml'
#define BRUMLE_AU_MANUFACTURER  'JPis'

// The component bundle's identifier (CFBundleIdentifier in Resources/AudioUnit-Info.plist) and the
// class in it that makes the plug-in's window.
#define BRUMLE_AU_BUNDLE_ID     "io.jp4.brumle.audiounit"
#define BRUMLE_AU_VIEW_CLASS    "BrumleAUViewFactory"

#include <AudioToolbox/AudioToolbox.h>

// Properties of the unit beyond Apple's, for its own window (global scope).
//   Engine:       read only. The unit's BrumleEngine* (size: one pointer). The window reads and
//                 sets what is not an Audio Unit parameter through it (the pads, their notes and
//                 groups, the mode) and plays its on-screen keys and pads. The engine lives as
//                 long as the unit.
//   StateChanged: write only, any UInt32. The window sets it after it changed the pads or the
//                 mode through the engine; the unit then tells the host its saved state
//                 (kAudioUnitProperty_ClassInfo) changed, so that the project is marked edited.
enum
{
    kBrumleProperty_Engine       = 64001,
    kBrumleProperty_StateChanged = 64002
};

#ifdef __cplusplus
extern "C" {
#endif

// The factory function a host looks up by name (AudioUnit-Info.plist, factoryFunction). It is
// defined by AUSDK_COMPONENT_ENTRY in BrumleAU.cpp; declared here for code that registers the
// Audio Unit with its own process, as the tests do.
void* BrumleAUFactory(const AudioComponentDescription* inDesc);

#ifdef __cplusplus
}
#endif

#endif // BRUMLE_AU_H
