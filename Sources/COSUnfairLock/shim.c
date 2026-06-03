//
// QuillUI os_unfair_lock shim — non-reentrant spinlock over C11 atomics.
// See include/os_unfair_lock_compat.h.
//
#include "os_unfair_lock_compat.h"

#include <stdatomic.h>
#include <sched.h>

void os_unfair_lock_lock(os_unfair_lock_t lock) {
    _Atomic uint32_t *p = (_Atomic uint32_t *)&lock->_os_unfair_lock_opaque;
    uint32_t expected = 0;
    while (!atomic_compare_exchange_weak_explicit(
               p, &expected, 1u, memory_order_acquire, memory_order_relaxed)) {
        expected = 0;
        sched_yield();
    }
}

void os_unfair_lock_unlock(os_unfair_lock_t lock) {
    _Atomic uint32_t *p = (_Atomic uint32_t *)&lock->_os_unfair_lock_opaque;
    atomic_store_explicit(p, 0u, memory_order_release);
}

int os_unfair_lock_trylock(os_unfair_lock_t lock) {
    _Atomic uint32_t *p = (_Atomic uint32_t *)&lock->_os_unfair_lock_opaque;
    uint32_t expected = 0;
    return atomic_compare_exchange_strong_explicit(
               p, &expected, 1u, memory_order_acquire, memory_order_relaxed) ? 1 : 0;
}

// Apple's asserts are fatal ownership checks; os_unfair_lock stores no owner id,
// so a faithful owner check isn't available from the lock word alone. These are
// debug aids — keep them as no-ops on Linux (the lock/unlock semantics are real).
void os_unfair_lock_assert_owner(os_unfair_lock_t lock) { (void)lock; }
void os_unfair_lock_assert_not_owner(os_unfair_lock_t lock) { (void)lock; }
