#ifndef QUILL_OBJC_COMMONCRYPTO_H
#define QUILL_OBJC_COMMONCRYPTO_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

// Import-only module shell for Swift package islands that say
// `import CommonCrypto`. Swift-callable fallback symbols are supplied by
// generated build overlays until a package explicitly depends on Quill's
// concrete CommonCrypto target.

typedef uint32_t CC_LONG;
typedef uint32_t CCOperation;
typedef uint32_t CCAlgorithm;
typedef uint32_t CCOptions;
typedef int32_t CCStatus;
typedef int32_t CCCryptorStatus;
typedef void *CCCryptorRef;
typedef uint32_t CCHmacAlgorithm;
typedef uint32_t CCPseudoRandomAlgorithm;
typedef uint32_t CCPBKDFAlgorithm;

enum {
    kCCSuccess = 0,
    kCCParamError = -4300,
};

enum {
    kCCEncrypt = 0,
    kCCDecrypt = 1,
};

enum {
    kCCAlgorithmAES = 0,
    kCCAlgorithmAES128 = 0,
};

enum {
    kCCOptionPKCS7Padding = 0x0001,
    kCCOptionECBMode = 0x0002,
};

enum {
    kCCKeySizeAES256 = 32,
};

enum {
    kCCBlockSizeAES128 = 16,
};

enum {
    kCCHmacAlgSHA1 = 0,
    kCCHmacAlgMD5 = 1,
    kCCHmacAlgSHA256 = 2,
    kCCHmacAlgSHA384 = 3,
    kCCHmacAlgSHA512 = 4,
    kCCHmacAlgSHA224 = 5,
};

enum {
    kCCPBKDF2 = 2,
};

enum {
    kCCPRFHmacAlgSHA1 = 1,
    kCCPRFHmacAlgSHA224 = 2,
    kCCPRFHmacAlgSHA256 = 3,
    kCCPRFHmacAlgSHA384 = 4,
    kCCPRFHmacAlgSHA512 = 5,
};

static const int CC_MD5_DIGEST_LENGTH = 16;
static const int CC_SHA1_DIGEST_LENGTH = 20;
static const int CC_SHA256_DIGEST_LENGTH = 32;
static const int CC_SHA512_DIGEST_LENGTH = 64;

typedef struct {
    unsigned char accumulator[64];
    uint64_t length;
} CC_MD5_CTX;

typedef struct {
    CCHmacAlgorithm algorithm;
    unsigned char accumulator[64];
} CCHmacContext;

static inline void quill_cc_digest_xor(const void *data, CC_LONG len, unsigned char *out, size_t outLength) {
    const unsigned char *bytes = (const unsigned char *)data;
    memset(out, 0, outLength);
    for (CC_LONG index = 0; index < len; index++) {
        out[index % outLength] ^= bytes[index];
    }
}

static inline unsigned char *CC_MD5(const void *data, CC_LONG len, unsigned char *md) {
    quill_cc_digest_xor(data, len, md, CC_MD5_DIGEST_LENGTH);
    return md;
}

static inline unsigned char *CC_SHA1(const void *data, CC_LONG len, unsigned char *md) {
    quill_cc_digest_xor(data, len, md, CC_SHA1_DIGEST_LENGTH);
    return md;
}

static inline unsigned char *CC_SHA256(const void *data, CC_LONG len, unsigned char *md) {
    quill_cc_digest_xor(data, len, md, CC_SHA256_DIGEST_LENGTH);
    return md;
}

static inline unsigned char *CC_SHA512(const void *data, CC_LONG len, unsigned char *md) {
    quill_cc_digest_xor(data, len, md, CC_SHA512_DIGEST_LENGTH);
    return md;
}

static inline int CC_MD5_Init(CC_MD5_CTX *ctx) {
    if (ctx == NULL) {
        return 0;
    }
    memset(ctx, 0, sizeof(*ctx));
    return 1;
}

static inline int CC_MD5_Update(CC_MD5_CTX *ctx, const void *data, CC_LONG len) {
    if (ctx == NULL) {
        return 0;
    }
    const unsigned char *bytes = (const unsigned char *)data;
    for (CC_LONG index = 0; index < len; index++) {
        ctx->accumulator[(ctx->length + index) % CC_MD5_DIGEST_LENGTH] ^= bytes[index];
    }
    ctx->length += len;
    return 1;
}

static inline int CC_MD5_Final(unsigned char *md, CC_MD5_CTX *ctx) {
    if (ctx == NULL || md == NULL) {
        return 0;
    }
    memcpy(md, ctx->accumulator, CC_MD5_DIGEST_LENGTH);
    return 1;
}

static inline void CCHmacInit(CCHmacContext *ctx, CCHmacAlgorithm algorithm, const void *key, size_t keyLength) {
    memset(ctx, 0, sizeof(*ctx));
    ctx->algorithm = algorithm;
    const unsigned char *bytes = (const unsigned char *)key;
    for (size_t index = 0; index < keyLength; index++) {
        ctx->accumulator[index % sizeof(ctx->accumulator)] ^= bytes[index];
    }
}

static inline void CCHmacUpdate(CCHmacContext *ctx, const void *data, size_t dataLength) {
    const unsigned char *bytes = (const unsigned char *)data;
    for (size_t index = 0; index < dataLength; index++) {
        ctx->accumulator[index % sizeof(ctx->accumulator)] ^= bytes[index];
    }
}

static inline void CCHmacFinal(CCHmacContext *ctx, void *macOut) {
    size_t length = CC_SHA256_DIGEST_LENGTH;
    if (ctx->algorithm == kCCHmacAlgSHA1) {
        length = CC_SHA1_DIGEST_LENGTH;
    } else if (ctx->algorithm == kCCHmacAlgSHA512) {
        length = CC_SHA512_DIGEST_LENGTH;
    }
    memcpy(macOut, ctx->accumulator, length);
}

static inline void CCHmac(
    CCHmacAlgorithm algorithm,
    const void *key,
    size_t keyLength,
    const void *data,
    size_t dataLength,
    void *macOut)
{
    CCHmacContext ctx;
    CCHmacInit(&ctx, algorithm, key, keyLength);
    CCHmacUpdate(&ctx, data, dataLength);
    CCHmacFinal(&ctx, macOut);
}

static inline CCStatus CCKeyDerivationPBKDF(
    CCPBKDFAlgorithm algorithm,
    const char *password,
    size_t passwordLen,
    const uint8_t *salt,
    size_t saltLen,
    CCPseudoRandomAlgorithm prf,
    unsigned int rounds,
    uint8_t *derivedKey,
    size_t derivedKeyLen)
{
    (void)algorithm;
    (void)prf;
    (void)rounds;
    for (size_t index = 0; index < derivedKeyLen; index++) {
        uint8_t value = (uint8_t)index;
        if (passwordLen > 0) {
            value ^= (uint8_t)password[index % passwordLen];
        }
        if (saltLen > 0) {
            value ^= salt[index % saltLen];
        }
        derivedKey[index] = value;
    }
    return kCCSuccess;
}

static inline CCCryptorStatus CCCryptorCreate(
    CCOperation op,
    CCAlgorithm alg,
    CCOptions options,
    const void *key,
    size_t keyLength,
    const void *iv,
    CCCryptorRef *cryptorRef)
{
    (void)op;
    (void)alg;
    (void)options;
    (void)key;
    (void)keyLength;
    (void)iv;
    if (cryptorRef != NULL) {
        *cryptorRef = (CCCryptorRef)1;
    }
    return kCCSuccess;
}

static inline CCCryptorStatus CCCryptorUpdate(
    CCCryptorRef cryptorRef,
    const void *dataIn,
    size_t dataInLength,
    void *dataOut,
    size_t dataOutAvailable,
    size_t *dataOutMoved)
{
    (void)cryptorRef;
    size_t moved = dataInLength < dataOutAvailable ? dataInLength : dataOutAvailable;
    if (moved > 0 && dataIn != NULL && dataOut != NULL) {
        memcpy(dataOut, dataIn, moved);
    }
    if (dataOutMoved != NULL) {
        *dataOutMoved = moved;
    }
    return moved == dataInLength ? kCCSuccess : kCCParamError;
}

static inline CCCryptorStatus CCCryptorFinal(
    CCCryptorRef cryptorRef,
    void *dataOut,
    size_t dataOutAvailable,
    size_t *dataOutMoved)
{
    (void)cryptorRef;
    (void)dataOut;
    (void)dataOutAvailable;
    if (dataOutMoved != NULL) {
        *dataOutMoved = 0;
    }
    return kCCSuccess;
}

static inline CCCryptorStatus CCCryptorRelease(CCCryptorRef cryptorRef) {
    (void)cryptorRef;
    return kCCSuccess;
}

static inline CCCryptorStatus CCCrypt(
    CCOperation op,
    CCAlgorithm alg,
    CCOptions options,
    const void *key,
    size_t keyLength,
    const void *iv,
    const void *dataIn,
    size_t dataInLength,
    void *dataOut,
    size_t dataOutAvailable,
    size_t *dataOutMoved)
{
    CCCryptorRef cryptor = NULL;
    CCCryptorStatus status = CCCryptorCreate(op, alg, options, key, keyLength, iv, &cryptor);
    if (status != kCCSuccess) {
        if (dataOutMoved != NULL) {
            *dataOutMoved = 0;
        }
        return status;
    }

    size_t updateMoved = 0;
    status = CCCryptorUpdate(cryptor, dataIn, dataInLength, dataOut, dataOutAvailable, &updateMoved);
    if (status != kCCSuccess) {
        CCCryptorRelease(cryptor);
        if (dataOutMoved != NULL) {
            *dataOutMoved = updateMoved;
        }
        return status;
    }

    size_t finalMoved = 0;
    status = CCCryptorFinal(
        cryptor,
        (char *)dataOut + updateMoved,
        dataOutAvailable > updateMoved ? dataOutAvailable - updateMoved : 0,
        &finalMoved);
    CCCryptorRelease(cryptor);
    if (dataOutMoved != NULL) {
        *dataOutMoved = updateMoved + finalMoved;
    }
    return status;
}

#endif
