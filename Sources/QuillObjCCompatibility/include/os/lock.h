#ifndef QUILL_OBJC_OS_LOCK_H
#define QUILL_OBJC_OS_LOCK_H

#include <stdbool.h>
#include <stdint.h>

typedef struct os_unfair_lock_s {
    uint32_t _os_unfair_lock_opaque;
} os_unfair_lock, *os_unfair_lock_t;

#define OS_UNFAIR_LOCK_INIT ((struct os_unfair_lock_s){0})

static inline void os_unfair_lock_lock(os_unfair_lock_t lock) {
    (void)lock;
}

static inline void os_unfair_lock_unlock(os_unfair_lock_t lock) {
    (void)lock;
}

static inline int os_unfair_lock_trylock(os_unfair_lock_t lock) {
    (void)lock;
    return 1;
}

static inline void os_unfair_lock_assert_owner(os_unfair_lock_t lock) {
    (void)lock;
}

static inline void os_unfair_lock_assert_not_owner(os_unfair_lock_t lock) {
    (void)lock;
}

static inline int32_t OSAtomicIncrement32(volatile int32_t *value) {
    return __sync_add_and_fetch(value, 1);
}

static inline int32_t OSAtomicDecrement32(volatile int32_t *value) {
    return __sync_sub_and_fetch(value, 1);
}

static inline bool OSAtomicCompareAndSwap32(int32_t oldValue, int32_t newValue, volatile int32_t *theValue) {
    return __sync_bool_compare_and_swap(theValue, oldValue, newValue);
}

#endif
