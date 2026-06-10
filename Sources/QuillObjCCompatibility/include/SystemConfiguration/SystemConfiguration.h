#ifndef QUILL_OBJC_SYSTEMCONFIGURATION_H
#define QUILL_OBJC_SYSTEMCONFIGURATION_H

#include <stdbool.h>
#include <stdint.h>
#include <strings.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>

#if defined(__linux__) && !defined(sin_len)
#define sin_len sin_zero[0]
#endif

#ifndef QUILL_OBJC_DISPATCH_QUEUE_T_TYPEDEF
#define QUILL_OBJC_DISPATCH_QUEUE_T_TYPEDEF
typedef void *dispatch_queue_t;
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef const struct __SCNetworkReachability *SCNetworkReachabilityRef;
typedef uint32_t SCNetworkReachabilityFlags;
typedef const void *(*SCNetworkReachabilityRetainCallBack)(const void *info);
typedef void (*SCNetworkReachabilityReleaseCallBack)(const void *info);
typedef CFStringRef (*SCNetworkReachabilityCopyDescriptionCallBack)(const void *info);
typedef void (*SCNetworkReachabilityCallBack)(
    SCNetworkReachabilityRef target,
    SCNetworkReachabilityFlags flags,
    void *info
);

typedef struct {
    CFIndex version;
    void *info;
    SCNetworkReachabilityRetainCallBack retain;
    SCNetworkReachabilityReleaseCallBack release;
    SCNetworkReachabilityCopyDescriptionCallBack copyDescription;
} SCNetworkReachabilityContext;

enum {
    kSCNetworkReachabilityFlagsTransientConnection = 1u << 0,
    kSCNetworkReachabilityFlagsReachable = 1u << 1,
    kSCNetworkReachabilityFlagsConnectionRequired = 1u << 2,
    kSCNetworkReachabilityFlagsConnectionOnTraffic = 1u << 3,
    kSCNetworkReachabilityFlagsInterventionRequired = 1u << 4,
    kSCNetworkReachabilityFlagsConnectionOnDemand = 1u << 5,
    kSCNetworkReachabilityFlagsIsLocalAddress = 1u << 16,
    kSCNetworkReachabilityFlagsIsDirect = 1u << 17,
    kSCNetworkReachabilityFlagsIsWWAN = 1u << 18,
    kSCNetworkReachabilityFlagsConnectionAutomatic = kSCNetworkReachabilityFlagsConnectionOnTraffic,
};

typedef const void *CFRunLoopRef;
typedef CFStringRef CFRunLoopMode;
static const CFRunLoopMode kCFRunLoopDefaultMode = (CFRunLoopMode)"kCFRunLoopDefaultMode";

static inline CFRunLoopRef CFRunLoopGetCurrent(void) {
    return (CFRunLoopRef)1;
}

static inline SCNetworkReachabilityRef SCNetworkReachabilityCreateWithAddress(
    CFAllocatorRef allocator,
    const struct sockaddr *address)
{
    (void)allocator;
    (void)address;
    return (SCNetworkReachabilityRef)1;
}

static inline SCNetworkReachabilityRef SCNetworkReachabilityCreateWithName(
    CFAllocatorRef allocator,
    const char *nodename)
{
    (void)allocator;
    (void)nodename;
    return (SCNetworkReachabilityRef)1;
}

static inline Boolean SCNetworkReachabilityGetFlags(
    SCNetworkReachabilityRef target,
    SCNetworkReachabilityFlags *flags)
{
    (void)target;
    if (flags != NULL) {
        *flags = kSCNetworkReachabilityFlagsReachable;
    }
    return true;
}

static inline Boolean SCNetworkReachabilitySetCallback(
    SCNetworkReachabilityRef target,
    SCNetworkReachabilityCallBack callout,
    SCNetworkReachabilityContext *context)
{
    (void)target;
    (void)callout;
    (void)context;
    return true;
}

static inline Boolean SCNetworkReachabilitySetDispatchQueue(
    SCNetworkReachabilityRef target,
    dispatch_queue_t queue)
{
    (void)target;
    (void)queue;
    return true;
}

static inline Boolean SCNetworkReachabilityScheduleWithRunLoop(
    SCNetworkReachabilityRef target,
    CFRunLoopRef runLoop,
    CFRunLoopMode runLoopMode)
{
    (void)target;
    (void)runLoop;
    (void)runLoopMode;
    return true;
}

static inline Boolean SCNetworkReachabilityUnscheduleFromRunLoop(
    SCNetworkReachabilityRef target,
    CFRunLoopRef runLoop,
    CFRunLoopMode runLoopMode)
{
    (void)target;
    (void)runLoop;
    (void)runLoopMode;
    return true;
}

#ifdef __cplusplus
}
#endif

#endif
