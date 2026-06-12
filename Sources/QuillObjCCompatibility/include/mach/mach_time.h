#ifndef QUILL_OBJC_MACH_TIME_H
#define QUILL_OBJC_MACH_TIME_H

#if defined(__APPLE__)
#include_next <mach/mach_time.h>
#else

#include <stdint.h>
#include <time.h>
#include <mach/mach.h>

typedef struct mach_timebase_info {
    uint32_t numer;
    uint32_t denom;
} mach_timebase_info_data_t;

static inline kern_return_t mach_timebase_info(mach_timebase_info_data_t *info) {
    if (info == NULL) {
        return KERN_FAILURE;
    }
    info->numer = 1;
    info->denom = 1;
    return KERN_SUCCESS;
}

static inline uint64_t mach_absolute_time(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        return 0;
    }
    return ((uint64_t)ts.tv_sec * 1000000000ull) + (uint64_t)ts.tv_nsec;
}

#endif

#endif
