#ifndef QUILL_IOKIT_PWR_MGT_COMPAT_H
#define QUILL_IOKIT_PWR_MGT_COMPAT_H

#include <stdint.h>
#include "IOKit.h"
#include <CoreFoundation/CoreFoundation.h>

typedef uint32_t IOPMAssertionID;
typedef int32_t IOPMAssertionLevel;
typedef kern_return_t IOReturn;
typedef const char *IOPMAssertionType;

static const IOPMAssertionLevel kIOPMAssertionLevelOff = 0;
static const IOPMAssertionLevel kIOPMAssertionLevelOn = 255;
static const IOPMAssertionID kIOPMNullAssertionID = 0;
static const IOPMAssertionType kIOPMAssertionTypeNoDisplaySleep = "NoDisplaySleepAssertion";
static const IOPMAssertionType kIOPMAssertionTypeNoIdleSleep = "NoIdleSleepAssertion";
static const IOPMAssertionType kIOPMAssertionTypePreventUserIdleDisplaySleep = "PreventUserIdleDisplaySleep";
static const IOPMAssertionType kIOPMAssertionTypePreventUserIdleSystemSleep = "PreventUserIdleSystemSleep";

static inline kern_return_t IOPMAssertionCreateWithName(
    IOPMAssertionType assertionType,
    IOPMAssertionLevel assertionLevel,
    const char *assertionName,
    IOPMAssertionID *assertionID
) {
    (void)assertionType;
    (void)assertionLevel;
    (void)assertionName;
    if (assertionID != 0) {
        *assertionID = kIOPMNullAssertionID;
    }
    return kIOReturnUnsupported;
}

static inline kern_return_t IOPMAssertionRelease(IOPMAssertionID assertionID) {
    (void)assertionID;
    return kIOReturnSuccess;
}

#endif
