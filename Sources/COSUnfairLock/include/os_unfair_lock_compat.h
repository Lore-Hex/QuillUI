//
// QuillUI Linux shim for Apple's <os/lock.h> os_unfair_lock.
//
// Signal's SignalServiceKit/Concurrency/TSMutex.swift `internal import os.lock`
// and wraps os_unfair_lock. The `os` framework's `lock` submodule does not exist
// on Linux (and QuillUI's `os` is a Swift module, which cannot expose a clang
// submodule). This C module provides the exact os_unfair_lock surface TSMutex
// uses, with Apple-compatible layout, implemented as a non-reentrant spinlock
// over C11 atomics. TSMutex's import is conditionally swapped to this module on
// Linux (see scripts/fetch-upstream.sh patch_signal_ios); its logic is unchanged.
//
#ifndef QUILL_OS_UNFAIR_LOCK_COMPAT_H
#define QUILL_OS_UNFAIR_LOCK_COMPAT_H

#include <stdint.h>

typedef struct os_unfair_lock_s {
    uint32_t _os_unfair_lock_opaque;
} os_unfair_lock, *os_unfair_lock_t;

#define OS_UNFAIR_LOCK_INIT ((struct os_unfair_lock_s){0})

typedef int32_t OSSpinLock;
#define OS_SPINLOCK_INIT 0

void os_unfair_lock_lock(os_unfair_lock_t lock);
void os_unfair_lock_unlock(os_unfair_lock_t lock);
int  os_unfair_lock_trylock(os_unfair_lock_t lock);
void os_unfair_lock_assert_owner(os_unfair_lock_t lock);
void os_unfair_lock_assert_not_owner(os_unfair_lock_t lock);

void OSSpinLockLock(volatile OSSpinLock *lock);
void OSSpinLockUnlock(volatile OSSpinLock *lock);
int  OSSpinLockTry(volatile OSSpinLock *lock);

#endif /* QUILL_OS_UNFAIR_LOCK_COMPAT_H */
