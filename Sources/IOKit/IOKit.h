#ifndef QUILL_IOKIT_COMPAT_H
#define QUILL_IOKIT_COMPAT_H

#include <stdint.h>
#include <CoreFoundation/CoreFoundation.h>

#ifndef QUILL_OBJC_DISPATCH_QUEUE_T_TYPEDEF
#define QUILL_OBJC_DISPATCH_QUEUE_T_TYPEDEF
typedef void *dispatch_queue_t;
#endif

typedef uint32_t io_object_t;
typedef io_object_t io_iterator_t;
typedef io_object_t io_service_t;
typedef io_object_t io_connect_t;
typedef uint32_t mach_port_t;
typedef int32_t kern_return_t;
typedef struct QuillIONotificationPort *IONotificationPortRef;
typedef void (*IOServiceMatchingCallback)(void *refcon, io_iterator_t iterator);

#define kIOMainPortDefault ((mach_port_t)0)
#define kIOMasterPortDefault ((mach_port_t)0)
#define kIOReturnSuccess ((kern_return_t)0)
#define kIOReturnUnsupported ((kern_return_t)-536870201)
#define kIOFirstMatchNotification "IOServiceFirstMatch"
#define kIOTerminatedNotification "IOServiceTerminate"
#define kIOPSNameKey "Name"
#define kIOPSTimeToEmptyKey "TimeToEmpty"
#define kIOPSTimeToFullChargeKey "TimeToFullCharge"

static inline IONotificationPortRef IONotificationPortCreate(mach_port_t mainPort) {
    (void)mainPort;
    return (IONotificationPortRef)0;
}

static inline void IONotificationPortDestroy(IONotificationPortRef notifyPort) {
    (void)notifyPort;
}

static inline void IONotificationPortSetDispatchQueue(
    IONotificationPortRef notifyPort,
    dispatch_queue_t queue
) {
    (void)notifyPort;
    (void)queue;
}

static inline void *IOServiceMatching(const char *name) {
    (void)name;
    return (void *)0;
}

static inline io_service_t IOServiceGetMatchingService(mach_port_t mainPort, const void *matching) {
    (void)mainPort;
    (void)matching;
    return 0;
}

static inline CFTypeRef IOPSCopyPowerSourcesInfo(void) {
    return (CFTypeRef)0;
}

static inline CFArrayRef IOPSCopyPowerSourcesList(CFTypeRef blob) {
    (void)blob;
    return (CFArrayRef)0;
}

static inline CFDictionaryRef IOPSGetPowerSourceDescription(CFTypeRef blob, CFTypeRef ps) {
    (void)blob;
    (void)ps;
    return (CFDictionaryRef)0;
}

static inline CFTypeRef IORegistryEntryCreateCFProperty(
    io_service_t entry,
    const char *key,
    CFTypeRef allocator,
    uint32_t options
) {
    (void)entry;
    (void)key;
    (void)allocator;
    (void)options;
    return (CFTypeRef)0;
}

static inline kern_return_t IOServiceClose(io_connect_t connect) {
    (void)connect;
    return kIOReturnSuccess;
}

static inline kern_return_t IOServiceAddMatchingNotification(
    IONotificationPortRef notifyPort,
    const char *notificationType,
    const void *matching,
    IOServiceMatchingCallback callback,
    void *refCon,
    io_iterator_t *notification
) {
    (void)notifyPort;
    (void)notificationType;
    (void)matching;
    (void)callback;
    (void)refCon;
    if (notification != 0) {
        *notification = 0;
    }
    return kIOReturnUnsupported;
}

static inline io_object_t IOIteratorNext(io_iterator_t iterator) {
    (void)iterator;
    return 0;
}

static inline kern_return_t IOObjectRelease(io_object_t object) {
    (void)object;
    return kIOReturnSuccess;
}

#endif
