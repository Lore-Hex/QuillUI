#ifndef QUILL_OBJC_MACH_H
#define QUILL_OBJC_MACH_H

#if defined(__APPLE__)
#include_next <mach/mach.h>
#else

#include <stdint.h>
#include <stdlib.h>

typedef int kern_return_t;
typedef uintptr_t vm_address_t;
typedef uintptr_t vm_size_t;
typedef int vm_prot_t;
typedef int vm_inherit_t;
typedef unsigned int mach_port_t;

#ifndef ERR_SUCCESS
#define ERR_SUCCESS 0
#endif

#ifndef KERN_SUCCESS
#define KERN_SUCCESS 0
#endif

#ifndef KERN_FAILURE
#define KERN_FAILURE 5
#endif

#ifndef VM_FLAGS_ANYWHERE
#define VM_FLAGS_ANYWHERE 1
#endif

#ifndef VM_INHERIT_DEFAULT
#define VM_INHERIT_DEFAULT 0
#endif

#ifndef round_page
#define round_page(x) ((((uintptr_t)(x)) + 4095U) & ~(uintptr_t)4095U)
#endif

static inline mach_port_t mach_task_self(void) {
    return 0;
}

static inline const char *mach_error_string(kern_return_t error_value) {
    (void)error_value;
    return "mach error (quill shim)";
}

static inline kern_return_t vm_allocate(
    mach_port_t target_task,
    vm_address_t *address,
    vm_size_t size,
    int flags
) {
    (void)target_task;
    (void)flags;
    if (address == NULL || size == 0) {
        return KERN_FAILURE;
    }
    void *memory = calloc(1, size);
    if (memory == NULL) {
        return KERN_FAILURE;
    }
    *address = (vm_address_t)memory;
    return KERN_SUCCESS;
}

static inline kern_return_t vm_deallocate(
    mach_port_t target_task,
    vm_address_t address,
    vm_size_t size
) {
    (void)target_task;
    (void)address;
    (void)size;
    return KERN_SUCCESS;
}

static inline kern_return_t vm_remap(
    mach_port_t target_task,
    vm_address_t *target_address,
    vm_size_t size,
    vm_address_t mask,
    int flags,
    mach_port_t source_task,
    vm_address_t source_address,
    int copy,
    vm_prot_t *cur_protection,
    vm_prot_t *max_protection,
    vm_inherit_t inheritance
) {
    (void)target_task;
    (void)mask;
    (void)flags;
    (void)source_task;
    (void)copy;
    (void)inheritance;
    if (target_address == NULL || source_address == 0) {
        return KERN_FAILURE;
    }
    *target_address = source_address + size;
    if (cur_protection != NULL) {
        *cur_protection = 0;
    }
    if (max_protection != NULL) {
        *max_protection = 0;
    }
    return KERN_SUCCESS;
}

#endif

#endif
