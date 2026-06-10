#ifndef QUILL_OBJC_SECURITY_SECRANDOM_H
#define QUILL_OBJC_SECURITY_SECRANDOM_H

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef int32_t OSStatus;
typedef const struct __SecRandom *SecRandomRef;

#ifndef errSecSuccess
#define errSecSuccess 0
#endif

static const SecRandomRef kSecRandomDefault = (SecRandomRef)0;

static inline OSStatus SecRandomCopyBytes(SecRandomRef rnd, size_t count, void *bytes) {
    (void)rnd;
    if (bytes == NULL || count == 0) {
        return errSecSuccess;
    }

    FILE *file = fopen("/dev/urandom", "rb");
    if (file != NULL) {
        size_t read_count = fread(bytes, 1, count, file);
        fclose(file);
        if (read_count == count) {
            return errSecSuccess;
        }
    }

    uint8_t *cursor = (uint8_t *)bytes;
    for (size_t index = 0; index < count; index++) {
        cursor[index] = (uint8_t)(rand() & 0xff);
    }
    return errSecSuccess;
}

#endif
