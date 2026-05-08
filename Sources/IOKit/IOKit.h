#ifndef QUILL_IOKIT_COMPAT_H
#define QUILL_IOKIT_COMPAT_H

#include <stdint.h>

#if __has_include(<dispatch/dispatch.h>)
#include <dispatch/dispatch.h>
#else
typedef void *dispatch_queue_t;
#endif

typedef uint32_t io_object_t;
typedef io_object_t io_iterator_t;
typedef io_object_t io_service_t;
typedef uint32_t mach_port_t;
typedef int32_t kern_return_t;
typedef struct QuillIONotificationPort *IONotificationPortRef;
typedef void (*IOServiceMatchingCallback)(void *refcon, io_iterator_t iterator);

#define kIOMainPortDefault ((mach_port_t)0)
#define kIOReturnSuccess ((kern_return_t)0)
#define kIOReturnUnsupported ((kern_return_t)-536870201)
#define kIOFirstMatchNotification "IOServiceFirstMatch"
#define kIOTerminatedNotification "IOServiceTerminate"

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
