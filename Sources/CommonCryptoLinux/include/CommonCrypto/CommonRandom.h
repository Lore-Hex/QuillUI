// Linux shim for CommonCrypto/CommonRandom.h.
//
// Upstream wireguard-apple's x25519.c calls CCRandomGenerateBytes(buf, n)
// to seed Curve25519 private keys. On Apple platforms that maps to
// CommonCrypto. On Linux we wire it to getrandom(2) (with a /dev/urandom
// fallback) so WireGuardKit's keypair generator works without any
// modification to the upstream C source.
//
// This header is *only* on the Linux include path — the real CommonCrypto
// framework wins on macOS via the SDK.

#ifndef QUILL_COMMONCRYPTO_COMMONRANDOM_H
#define QUILL_COMMONCRYPTO_COMMONRANDOM_H

#ifndef __APPLE__

#include <stddef.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/syscall.h>
#if defined(__linux__) && defined(SYS_getrandom)
#  include <linux/random.h>
#endif

typedef int CCRNGStatus;
#ifndef kCCSuccess
#  define kCCSuccess 0
#endif

static inline CCRNGStatus CCRandomGenerateBytes(void *bytes, size_t count) {
    if (bytes == 0 || count == 0) return kCCSuccess;
    size_t filled = 0;
#if defined(__linux__) && defined(SYS_getrandom)
    while (filled < count) {
        long r = syscall(SYS_getrandom, (uint8_t *)bytes + filled, count - filled, 0);
        if (r > 0) { filled += (size_t)r; continue; }
        if (r < 0) break; /* fall through to /dev/urandom */
    }
#endif
    if (filled < count) {
        int fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
        if (fd < 0) return -1;
        while (filled < count) {
            ssize_t r = read(fd, (uint8_t *)bytes + filled, count - filled);
            if (r <= 0) { close(fd); return -1; }
            filled += (size_t)r;
        }
        close(fd);
    }
    return kCCSuccess;
}

#endif /* !__APPLE__ */

#endif /* QUILL_COMMONCRYPTO_COMMONRANDOM_H */
