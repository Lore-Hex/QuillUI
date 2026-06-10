#ifndef QUILL_OBJC_SECURITY_H
#define QUILL_OBJC_SECURITY_H

#include <Security/SecRandom.h>
#include <Security/SecureTransport.h>

typedef struct __SecKey *SecKeyRef;

// Import-only module shell for Swift package islands that say `import Security`.
// Swift-callable fallback symbols are supplied by generated build overlays until
// a package explicitly depends on Quill's Swift `Security` target.

/* Inert keychain / SecKey C surface for Objective-C package islands
 * (BuildConfig's MTPkcs auth-key plumbing). There is no keychain on QuillOS:
 * lookups report errSecItemNotFound, key creation fails cleanly, and callers'
 * error paths run. CoreFoundation-shaped types alias the ObjC classes the
 * compat Foundation.h provides under toll-free bridging names. */
#if defined(__OBJC__)

#include <CoreFoundation/CoreFoundation.h>

typedef void *CFErrorRef;

#ifndef errSecItemNotFound
#define errSecItemNotFound (-25300)
#endif

#define kSecClass CFSTR("class")
#define kSecClassKey CFSTR("keys")
#define kSecClassGenericPassword CFSTR("genp")
#define kSecAttrKeyType CFSTR("type")
#define kSecAttrKeyTypeECSECPrimeRandom CFSTR("73")
#define kSecAttrKeySizeInBits CFSTR("bsiz")
#define kSecAttrIsPermanent CFSTR("perm")
#define kSecAttrApplicationTag CFSTR("atag")
#define kSecAttrAccessGroup CFSTR("agrp")
#define kSecAttrService CFSTR("svce")
#define kSecAttrAccount CFSTR("acct")
#define kSecPrivateKeyAttrs CFSTR("private")
#define kSecReturnRef CFSTR("r_Ref")
#define kSecReturnAttributes CFSTR("r_Attributes")
#define kSecValueData CFSTR("v_Data")

/* Callers write `(id)kCFBooleanTrue` (toll-free bridged on Apple), so the
 * expansion stays ObjC-typed. */
#ifndef kCFBooleanTrue
#define kCFBooleanTrue ((id)@YES)
#endif
#ifndef kCFBooleanFalse
#define kCFBooleanFalse ((id)@NO)
#endif

static inline OSStatus SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    (void)query;
    if (result != NULL) {
        *result = NULL;
    }
    return errSecItemNotFound;
}

static inline OSStatus SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    (void)attributes;
    if (result != NULL) {
        *result = NULL;
    }
    return errSecItemNotFound;
}

static inline OSStatus SecItemDelete(CFDictionaryRef query) {
    (void)query;
    return errSecItemNotFound;
}

static inline SecKeyRef SecKeyCreateRandomKey(CFDictionaryRef parameters, void *error) {
    (void)parameters;
    (void)error;
    return (SecKeyRef)0;
}

static inline SecKeyRef SecKeyCopyPublicKey(SecKeyRef key) {
    (void)key;
    return (SecKeyRef)0;
}

static inline CFDataRef SecKeyCopyExternalRepresentation(SecKeyRef key, void *error) {
    (void)key;
    (void)error;
    return (CFDataRef)0;
}

typedef CFStringRef SecKeyAlgorithm;
#define kSecKeyAlgorithmECIESEncryptionCofactorX963SHA256AESGCM CFSTR("eciesCofactorX963SHA256AESGCM")

static inline CFDataRef SecKeyCreateEncryptedData(SecKeyRef key, SecKeyAlgorithm algorithm, CFDataRef plaintext, void *error) {
    (void)key;
    (void)algorithm;
    (void)plaintext;
    (void)error;
    return (CFDataRef)0;
}

static inline CFDataRef SecKeyCreateDecryptedData(SecKeyRef key, SecKeyAlgorithm algorithm, CFDataRef ciphertext, void *error) {
    (void)key;
    (void)algorithm;
    (void)ciphertext;
    (void)error;
    return (CFDataRef)0;
}

#endif /* __OBJC__ */

#endif
