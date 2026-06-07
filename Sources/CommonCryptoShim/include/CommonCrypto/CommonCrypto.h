//
// QuillUI Linux shim for Apple's CommonCrypto — AES subset, backed by OpenSSL.
//
// Apple's CommonCrypto framework does not exist on Linux. Signal's
// SignalServiceKit uses its AES cryptor API (CipherContext, Cryptography,
// PaddingBucket, ProvisioningCipher): one-shot CCCrypt + the streaming
// CCCryptorCreate/Update/Final/Release, with AES in CBC/ECB and PKCS7 padding.
//
// This header declares exactly that surface with Apple-compatible signatures
// and constant values, so `import CommonCrypto` and the call sites compile
// unchanged. The implementation (shim.c) maps onto OpenSSL libcrypto's EVP API.
// Scope is deliberately the AES subset Signal needs; extend as new call sites
// appear.
//
#ifndef QUILL_COMMONCRYPTO_H
#define QUILL_COMMONCRYPTO_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - Types (Apple-compatible)

typedef uint32_t CCOperation;
typedef uint32_t CCAlgorithm;
typedef uint32_t CCOptions;
typedef int32_t  CCStatus;
typedef int32_t  CCCryptorStatus;

typedef struct _CCCryptor *CCCryptorRef;

// MARK: - Constants (match Apple's <CommonCrypto/CommonCryptor.h> values)

enum {
    kCCEncrypt = 0,
    kCCDecrypt = 1,
};

enum {
    kCCAlgorithmAES    = 0,
    kCCAlgorithmAES128 = 0,
};

enum {
    kCCOptionPKCS7Padding = 0x0001,
    kCCOptionECBMode      = 0x0002,
};

enum {
    kCCSuccess       = 0,
    kCCParamError    = -4300,
    kCCBufferTooSmall = -4301,
    kCCMemoryFailure = -4302,
    kCCAlignmentError = -4303,
    kCCDecodeError   = -4304,
    kCCUnimplemented = -4305,
};

enum {
    kCCBlockSizeAES128 = 16,
};

// MARK: - Streaming cryptor API

CCCryptorStatus CCCryptorCreate(
    CCOperation op,
    CCAlgorithm alg,
    CCOptions options,
    const void *key,
    size_t keyLength,
    const void *iv,
    CCCryptorRef *cryptorRef);

CCCryptorStatus CCCryptorUpdate(
    CCCryptorRef cryptorRef,
    const void *dataIn,
    size_t dataInLength,
    void *dataOut,
    size_t dataOutAvailable,
    size_t *dataOutMoved);

CCCryptorStatus CCCryptorFinal(
    CCCryptorRef cryptorRef,
    void *dataOut,
    size_t dataOutAvailable,
    size_t *dataOutMoved);

CCCryptorStatus CCCryptorRelease(CCCryptorRef cryptorRef);

size_t CCCryptorGetOutputLength(
    CCCryptorRef cryptorRef,
    size_t inputLength,
    bool final);

// MARK: - One-shot API

CCCryptorStatus CCCrypt(
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
    size_t *dataOutMoved);

#ifdef __cplusplus
}
#endif

#endif /* QUILL_COMMONCRYPTO_H */
