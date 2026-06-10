#ifndef QUILL_OBJC_CORESERVICES_H
#define QUILL_OBJC_CORESERVICES_H

#include <CoreFoundation/CoreFoundation.h>
#include <Foundation/Foundation.h>
#include <stdbool.h>
#include <stdint.h>
#include <sys/socket.h>

typedef const struct __CFHost *CFHostRef;
typedef const struct __CFSocket *CFSocketRef;
typedef const struct __CFRunLoop *CFRunLoopRef;
typedef const struct __CFRunLoopSource *CFRunLoopSourceRef;
typedef int CFSocketNativeHandle;
typedef uint32_t CFSocketCallBackType;
typedef uint32_t CFHostInfoType;

typedef struct {
    CFIndex version;
    void *info;
    const void *(*retain)(const void *info);
    void (*release)(const void *info);
    CFStringRef (*copyDescription)(const void *info);
} CFSocketContext;

typedef struct {
    CFIndex version;
    void *info;
    const void *(*retain)(const void *info);
    void (*release)(const void *info);
    CFStringRef (*copyDescription)(const void *info);
} CFHostClientContext;

typedef struct {
    CFIndex domain;
    SInt32 error;
} CFStreamError;

typedef void (*CFSocketCallBack)(
    CFSocketRef s,
    CFSocketCallBackType callbackType,
    CFDataRef address,
    const void *data,
    void *info
);

typedef void (*CFHostClientCallBack)(
    CFHostRef theHost,
    CFHostInfoType typeInfo,
    const CFStreamError *error,
    void *info
);

static const CFSocketCallBackType kCFSocketReadCallBack = 1U;
static const CFHostInfoType kCFHostAddresses = 0U;
static const CFIndex kCFStreamErrorDomainNetDB = 1;
static const CFIndex kCFHostErrorUnknown = 1;
static const CFIndex kCFHostErrorHostNotFound = 2;
#if defined(__OBJC__)
static NSString * const kCFGetAddrInfoFailureKey = @"kCFGetAddrInfoFailureKey";
static NSString * const kCFErrorDomainCFNetwork = @"kCFErrorDomainCFNetwork";
#else
static const CFStringRef kCFGetAddrInfoFailureKey = CFSTR("kCFGetAddrInfoFailureKey");
static const CFStringRef kCFErrorDomainCFNetwork = CFSTR("kCFErrorDomainCFNetwork");
#endif
static const CFStringRef kCFRunLoopDefaultMode = CFSTR("kCFRunLoopDefaultMode");

static inline CFRunLoopRef CFRunLoopGetCurrent(void) {
    return NULL;
}

static inline void CFRunLoopAddSource(CFRunLoopRef rl, CFRunLoopSourceRef source, CFStringRef mode) {
    (void)rl;
    (void)source;
    (void)mode;
}

static inline CFSocketNativeHandle CFSocketGetNative(CFSocketRef s) {
    (void)s;
    return -1;
}

static inline CFSocketRef CFSocketCreateWithNative(
    CFAllocatorRef allocator,
    CFSocketNativeHandle sock,
    CFSocketCallBackType callBackTypes,
    CFSocketCallBack callout,
    const CFSocketContext *context
) {
    (void)allocator;
    (void)sock;
    (void)callBackTypes;
    (void)callout;
    (void)context;
    return NULL;
}

static inline CFRunLoopSourceRef CFSocketCreateRunLoopSource(
    CFAllocatorRef allocator,
    CFSocketRef s,
    CFIndex order
) {
    (void)allocator;
    (void)s;
    (void)order;
    return NULL;
}

static inline void CFSocketInvalidate(CFSocketRef s) {
    (void)s;
}

static inline CFHostRef CFHostCreateWithName(CFAllocatorRef allocator, CFStringRef hostname) {
    (void)allocator;
    (void)hostname;
    return NULL;
}

static inline bool CFHostSetClient(
    CFHostRef theHost,
    CFHostClientCallBack clientCB,
    CFHostClientContext *clientContext
) {
    (void)theHost;
    (void)clientCB;
    (void)clientContext;
    return true;
}

static inline void CFHostScheduleWithRunLoop(CFHostRef theHost, CFRunLoopRef runLoop, CFStringRef runLoopMode) {
    (void)theHost;
    (void)runLoop;
    (void)runLoopMode;
}

static inline bool CFHostStartInfoResolution(CFHostRef theHost, CFHostInfoType info, CFStreamError *error) {
    (void)theHost;
    (void)info;
    if (error != NULL) {
        error->domain = 0;
        error->error = 0;
    }
    return false;
}

static inline void CFHostUnscheduleFromRunLoop(CFHostRef theHost, CFRunLoopRef runLoop, CFStringRef runLoopMode) {
    (void)theHost;
    (void)runLoop;
    (void)runLoopMode;
}

static inline CFArrayRef CFHostGetAddressing(CFHostRef theHost, bool *hasBeenResolved) {
    (void)theHost;
    if (hasBeenResolved != NULL) {
        *hasBeenResolved = false;
    }
    return NULL;
}

#endif
