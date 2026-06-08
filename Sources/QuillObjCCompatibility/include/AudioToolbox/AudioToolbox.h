#ifndef QUILL_OBJC_AUDIOTOOLBOX_H
#define QUILL_OBJC_AUDIOTOOLBOX_H

#include <Foundation/Foundation.h>
#include <stdint.h>

typedef int32_t OSStatus;
typedef uint32_t OSType;
typedef uint32_t AudioUnitPropertyID;
typedef uint32_t AudioUnitScope;
typedef uint32_t AudioUnitElement;

typedef struct OpaqueAudioComponent *AudioComponent;
typedef struct OpaqueAudioUnit *AudioUnit;
typedef AudioUnit AudioComponentInstance;

static const OSStatus noErr = 0;

typedef struct AudioComponentDescription {
    OSType componentType;
    OSType componentSubType;
    OSType componentManufacturer;
    UInt32 componentFlags;
    UInt32 componentFlagsMask;
} AudioComponentDescription;

static const OSType kAudioUnitType_Output = 0x61756f75U;
static const OSType kAudioUnitSubType_VoiceProcessingIO = 0x7670696fU;
static const OSType kAudioUnitManufacturer_Apple = 0x6170706cU;
static const AudioUnitScope kAudioUnitScope_Global = 0;
static const AudioUnitPropertyID kAUVoiceIOProperty_MuteOutput = 2104;
static const AudioUnitPropertyID kAUVoiceIOProperty_MutedSpeechActivityEventListener = 2106;

typedef enum AUVoiceIOSpeechActivityEvent : int32_t {
    kAUVoiceIOSpeechActivityHasStarted = 0,
    kAUVoiceIOSpeechActivityHasEnded = 1
} AUVoiceIOSpeechActivityEvent;

typedef void (^AUVoiceIOMutedSpeechActivityEventListener)(AUVoiceIOSpeechActivityEvent event);

static inline AudioComponent AudioComponentFindNext(AudioComponent inComponent, const AudioComponentDescription *inDesc) {
    (void)inComponent;
    (void)inDesc;
    return (AudioComponent)1;
}

static inline OSStatus AudioComponentInstanceNew(AudioComponent inComponent, AudioComponentInstance *outInstance) {
    if (inComponent == NULL || outInstance == NULL) {
        return -1;
    }
    *outInstance = (AudioComponentInstance)inComponent;
    return noErr;
}

static inline OSStatus AudioComponentInstanceDispose(AudioComponentInstance inInstance) {
    (void)inInstance;
    return noErr;
}

static inline OSStatus AudioUnitSetProperty(
    AudioUnit inUnit,
    AudioUnitPropertyID inID,
    AudioUnitScope inScope,
    AudioUnitElement inElement,
    const void *inData,
    UInt32 inDataSize
) {
    (void)inUnit;
    (void)inID;
    (void)inScope;
    (void)inElement;
    (void)inData;
    (void)inDataSize;
    return noErr;
}

static inline OSStatus AudioUnitInitialize(AudioUnit inUnit) {
    (void)inUnit;
    return noErr;
}

static inline OSStatus AudioUnitUninitialize(AudioUnit inUnit) {
    (void)inUnit;
    return noErr;
}

static inline OSStatus AudioOutputUnitStart(AudioUnit ci) {
    (void)ci;
    return noErr;
}

static inline OSStatus AudioOutputUnitStop(AudioUnit ci) {
    (void)ci;
    return noErr;
}

#endif
