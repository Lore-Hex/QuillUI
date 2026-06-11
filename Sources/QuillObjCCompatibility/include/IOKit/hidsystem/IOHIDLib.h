#ifndef QUILL_OBJC_IOHIDLIB_H
#define QUILL_OBJC_IOHIDLIB_H

#include <stdbool.h>
#include <CoreFoundation/CoreFoundation.h>

typedef int kern_return_t;
typedef uint32_t mach_port_t;
typedef uint32_t io_iterator_t;
typedef uint32_t io_registry_entry_t;
typedef uint32_t io_object_t;

static const mach_port_t kIOMasterPortDefault = 0;
static const kern_return_t KERN_SUCCESS = 0;

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

static inline CFDictionaryRef IOServiceMatching(const char *name) {
    (void)name;
    return NULL;
}

static inline kern_return_t IOServiceGetMatchingServices(mach_port_t masterPort, CFDictionaryRef matching, io_iterator_t *existing) {
    (void)masterPort;
    (void)matching;
    if (existing != NULL) {
        *existing = 0;
    }
    return -1;
}

static inline io_registry_entry_t IOIteratorNext(io_iterator_t iterator) {
    (void)iterator;
    return 0;
}

static inline kern_return_t IORegistryEntryCreateCFProperties(io_registry_entry_t entry, CFMutableDictionaryRef *properties, CFAllocatorRef allocator, uint32_t options) {
    (void)entry;
    (void)allocator;
    (void)options;
    if (properties != NULL) {
        *properties = NULL;
    }
    return -1;
}

static inline kern_return_t IOObjectRelease(io_object_t object) {
    (void)object;
    return KERN_SUCCESS;
}

#endif
