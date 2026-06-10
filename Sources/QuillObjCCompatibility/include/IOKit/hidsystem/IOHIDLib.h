#ifndef QUILL_OBJC_IOHIDLIB_H
#define QUILL_OBJC_IOHIDLIB_H

#include <stdbool.h>

typedef enum IOHIDRequestType : int {
    kIOHIDRequestTypeListenEvent = 1
} IOHIDRequestType;

typedef enum IOHIDAccessType : int {
    kIOHIDAccessTypeGranted = 0,
    kIOHIDAccessTypeDenied = 1,
    kIOHIDAccessTypeUnknown = 2
} IOHIDAccessType;

static inline bool IOHIDRequestAccess(IOHIDRequestType requestType) {
    (void)requestType;
    return false;
}

static inline IOHIDAccessType IOHIDCheckAccess(IOHIDRequestType requestType) {
    (void)requestType;
    return kIOHIDAccessTypeDenied;
}

#endif
