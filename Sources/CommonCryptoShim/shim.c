//
// QuillUI CommonCrypto shim — AES, implemented over OpenSSL libcrypto (EVP).
// See include/CommonCrypto/CommonCrypto.h for the surface + rationale.
//
#include <CommonCrypto/CommonCrypto.h>

#if __has_include(<CCryptoBoringSSL_evp.h>)
#include <CCryptoBoringSSL_evp.h>
#else
#include <openssl/evp.h>
#endif
#include <stdlib.h>
#include <string.h>

struct _CCCryptor {
    EVP_CIPHER_CTX *ctx;
    size_t blockSize;
};

static const EVP_CIPHER *quill_pick_cipher(CCAlgorithm alg, size_t keyLength, CCOptions options) {
    if (alg != kCCAlgorithmAES) {
        return NULL;
    }
    int ecb = (options & kCCOptionECBMode) != 0;
    switch (keyLength) {
        case 16: return ecb ? EVP_aes_128_ecb() : EVP_aes_128_cbc();
        case 24: return ecb ? EVP_aes_192_ecb() : EVP_aes_192_cbc();
        case 32: return ecb ? EVP_aes_256_ecb() : EVP_aes_256_cbc();
        default: return NULL;
    }
}

CCCryptorStatus CCCryptorCreate(
    CCOperation op,
    CCAlgorithm alg,
    CCOptions options,
    const void *key,
    size_t keyLength,
    const void *iv,
    CCCryptorRef *cryptorRef)
{
    if (!cryptorRef || !key) {
        return kCCParamError;
    }
    const EVP_CIPHER *cipher = quill_pick_cipher(alg, keyLength, options);
    if (!cipher) {
        return kCCParamError;
    }
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) {
        return kCCMemoryFailure;
    }
    int enc = (op == (CCOperation)kCCEncrypt) ? 1 : 0;
    if (EVP_CipherInit_ex(ctx, cipher, NULL,
                          (const unsigned char *)key,
                          (const unsigned char *)iv, enc) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        return kCCParamError;
    }
    // CommonCrypto: PKCS7 padding only when requested; otherwise none.
    EVP_CIPHER_CTX_set_padding(ctx, (options & kCCOptionPKCS7Padding) ? 1 : 0);

    struct _CCCryptor *c = (struct _CCCryptor *)malloc(sizeof(struct _CCCryptor));
    if (!c) {
        EVP_CIPHER_CTX_free(ctx);
        return kCCMemoryFailure;
    }
    c->ctx = ctx;
    c->blockSize = (size_t)EVP_CIPHER_block_size(cipher);
    *cryptorRef = c;
    return kCCSuccess;
}

CCCryptorStatus CCCryptorUpdate(
    CCCryptorRef cryptorRef,
    const void *dataIn,
    size_t dataInLength,
    void *dataOut,
    size_t dataOutAvailable,
    size_t *dataOutMoved)
{
    if (!cryptorRef || !cryptorRef->ctx) {
        return kCCParamError;
    }
    // EVP may emit up to dataInLength + blockSize - 1 bytes.
    if (dataOutAvailable + 1 < dataInLength + cryptorRef->blockSize) {
        // Tolerate exact-fit callers; only reject when clearly too small.
        if (dataOutAvailable < dataInLength) {
            return kCCBufferTooSmall;
        }
    }
    int outl = 0;
    if (EVP_CipherUpdate(cryptorRef->ctx,
                         (unsigned char *)dataOut, &outl,
                         (const unsigned char *)dataIn, (int)dataInLength) != 1) {
        return kCCDecodeError;
    }
    if (dataOutMoved) {
        *dataOutMoved = (size_t)outl;
    }
    return kCCSuccess;
}

CCCryptorStatus CCCryptorFinal(
    CCCryptorRef cryptorRef,
    void *dataOut,
    size_t dataOutAvailable,
    size_t *dataOutMoved)
{
    if (!cryptorRef || !cryptorRef->ctx) {
        return kCCParamError;
    }
    if (dataOutAvailable < cryptorRef->blockSize) {
        // Final may emit up to one padding block.
        // (No-padding ciphers emit 0; allow that.)
    }
    int outl = 0;
    if (EVP_CipherFinal_ex(cryptorRef->ctx, (unsigned char *)dataOut, &outl) != 1) {
        return kCCDecodeError;
    }
    if (dataOutMoved) {
        *dataOutMoved = (size_t)outl;
    }
    return kCCSuccess;
}

CCCryptorStatus CCCryptorRelease(CCCryptorRef cryptorRef)
{
    if (cryptorRef) {
        if (cryptorRef->ctx) {
            EVP_CIPHER_CTX_free(cryptorRef->ctx);
        }
        free(cryptorRef);
    }
    return kCCSuccess;
}

size_t CCCryptorGetOutputLength(
    CCCryptorRef cryptorRef,
    size_t inputLength,
    bool final)
{
    (void)final;
    size_t blockSize = cryptorRef ? cryptorRef->blockSize : (size_t)kCCBlockSizeAES128;
    // Safe upper bound covering a buffered partial block + padding block.
    return inputLength + blockSize;
}

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
    size_t *dataOutMoved)
{
    CCCryptorRef cryptor = NULL;
    CCCryptorStatus s = CCCryptorCreate(op, alg, options, key, keyLength, iv, &cryptor);
    if (s != kCCSuccess) {
        return s;
    }
    size_t moved1 = 0;
    size_t moved2 = 0;
    s = CCCryptorUpdate(cryptor, dataIn, dataInLength, dataOut, dataOutAvailable, &moved1);
    if (s != kCCSuccess) {
        CCCryptorRelease(cryptor);
        return s;
    }
    s = CCCryptorFinal(cryptor,
                       (unsigned char *)dataOut + moved1,
                       dataOutAvailable - moved1, &moved2);
    if (s != kCCSuccess) {
        CCCryptorRelease(cryptor);
        return s;
    }
    if (dataOutMoved) {
        *dataOutMoved = moved1 + moved2;
    }
    CCCryptorRelease(cryptor);
    return kCCSuccess;
}
