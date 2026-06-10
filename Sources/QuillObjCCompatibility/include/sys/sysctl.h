#ifndef QUILL_OBJC_SYS_SYSCTL_H
#define QUILL_OBJC_SYS_SYSCTL_H

#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#ifndef CTL_KERN
#define CTL_KERN 1
#endif

#ifndef CTL_HW
#define CTL_HW 6
#endif

#ifndef KERN_BOOTTIME
#define KERN_BOOTTIME 21
#endif

#ifndef HW_NCPU
#define HW_NCPU 3
#endif

static inline int quill_sysctl_copy_value(const void *value, size_t valueSize, void *oldp, size_t *oldlenp) {
    if (oldlenp == NULL) {
        errno = EINVAL;
        return -1;
    }
    if (oldp == NULL) {
        *oldlenp = valueSize;
        return 0;
    }
    size_t copySize = *oldlenp < valueSize ? *oldlenp : valueSize;
    memcpy(oldp, value, copySize);
    *oldlenp = valueSize;
    return 0;
}

static inline int quill_sysctl_copy_cstring(const char *value, void *oldp, size_t *oldlenp) {
    return quill_sysctl_copy_value(value, strlen(value) + 1, oldp, oldlenp);
}

static inline int sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    (void)newp;
    (void)newlen;
    if (name == NULL) {
        errno = EINVAL;
        return -1;
    }

    if (strcmp(name, "hw.ncpu") == 0 || strcmp(name, "hw.logicalcpu") == 0) {
        long cpuCount = sysconf(_SC_NPROCESSORS_ONLN);
        int value = cpuCount > 0 ? (int)cpuCount : 1;
        return quill_sysctl_copy_value(&value, sizeof(value), oldp, oldlenp);
    }

    if (strcmp(name, "hw.memsize") == 0) {
        uint64_t value = 0;
#if defined(_SC_PHYS_PAGES) && defined(_SC_PAGESIZE)
        long pages = sysconf(_SC_PHYS_PAGES);
        long pageSize = sysconf(_SC_PAGESIZE);
        if (pages > 0 && pageSize > 0) {
            value = (uint64_t)pages * (uint64_t)pageSize;
        }
#endif
        return quill_sysctl_copy_value(&value, sizeof(value), oldp, oldlenp);
    }

    if (strcmp(name, "hw.model") == 0) {
        return quill_sysctl_copy_cstring("Linux", oldp, oldlenp);
    }

    if (strcmp(name, "kern.osversion") == 0) {
        return quill_sysctl_copy_cstring("Linux", oldp, oldlenp);
    }

    errno = ENOENT;
    return -1;
}

static inline int sysctl(int *name, unsigned int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    (void)newp;
    (void)newlen;
    if (name == NULL || namelen == 0) {
        errno = EINVAL;
        return -1;
    }

    if (namelen >= 2 && name[0] == CTL_KERN && name[1] == KERN_BOOTTIME) {
        struct timeval value;
        value.tv_sec = time(NULL);
        value.tv_usec = 0;
        return quill_sysctl_copy_value(&value, sizeof(value), oldp, oldlenp);
    }

    if (namelen >= 2 && name[0] == CTL_HW && name[1] == HW_NCPU) {
        return sysctlbyname("hw.ncpu", oldp, oldlenp, NULL, 0);
    }

    errno = ENOENT;
    return -1;
}

#endif
