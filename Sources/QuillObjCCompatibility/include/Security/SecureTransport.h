#ifndef QUILL_OBJC_SECURETRANSPORT_H
#define QUILL_OBJC_SECURETRANSPORT_H

#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef int32_t OSStatus;
typedef struct __QuillSSLContext *SSLContextRef;
typedef const void *SSLConnectionRef;
typedef uint16_t SSLCipherSuite;
typedef uint32_t SSLProtocol;
typedef uint32_t SSLProtocolSide;
typedef uint32_t SSLConnectionType;

typedef OSStatus (*SSLReadFunc)(SSLConnectionRef connection, void *data, size_t *dataLength);
typedef OSStatus (*SSLWriteFunc)(SSLConnectionRef connection, const void *data, size_t *dataLength);

#ifndef noErr
#define noErr ((OSStatus)0)
#endif

static const OSStatus errSSLWouldBlock = -9803;
static const OSStatus errSSLClosedGraceful = -9805;
static const OSStatus errSSLClosedAbort = -9806;

static const SSLProtocolSide kSSLClientSide = 1;
static const SSLProtocolSide kSSLServerSide = 2;
static const SSLConnectionType kSSLStreamType = 0;

static const SSLProtocol kSSLProtocolUnknown = 0;
static const SSLProtocol kSSLProtocol2 = 1;
static const SSLProtocol kSSLProtocol3 = 2;
static const SSLProtocol kTLSProtocol1 = 4;
static const SSLProtocol kTLSProtocol11 = 7;
static const SSLProtocol kTLSProtocol12 = 8;
static const SSLProtocol kSSLProtocolAll = 255;

static inline SSLContextRef SSLCreateContext(
    CFAllocatorRef alloc,
    SSLProtocolSide protocolSide,
    SSLConnectionType connectionType
) {
    (void)alloc;
    (void)protocolSide;
    (void)connectionType;
    return NULL;
}

static inline OSStatus SSLNewContext(Boolean isServer, SSLContextRef *contextPtr) {
    (void)isServer;
    if (contextPtr != NULL) {
        *contextPtr = NULL;
    }
    return noErr;
}

static inline OSStatus SSLDisposeContext(SSLContextRef context) {
    (void)context;
    return noErr;
}

static inline OSStatus SSLClose(SSLContextRef context) {
    (void)context;
    return noErr;
}

static inline OSStatus SSLSetIOFuncs(SSLContextRef context, SSLReadFunc readFunc, SSLWriteFunc writeFunc) {
    (void)context;
    (void)readFunc;
    (void)writeFunc;
    return noErr;
}

static inline OSStatus SSLSetConnection(SSLContextRef context, SSLConnectionRef connection) {
    (void)context;
    (void)connection;
    return noErr;
}

static inline OSStatus SSLSetPeerDomainName(SSLContextRef context, const char *peerName, size_t peerNameLen) {
    (void)context;
    (void)peerName;
    (void)peerNameLen;
    return noErr;
}

static inline OSStatus SSLSetCertificate(SSLContextRef context, CFArrayRef certRefs) {
    (void)context;
    (void)certRefs;
    return noErr;
}

static inline OSStatus SSLSetAllowsAnyRoot(SSLContextRef context, Boolean allowsAnyRoot) {
    (void)context;
    (void)allowsAnyRoot;
    return noErr;
}

static inline OSStatus SSLSetAllowsExpiredRoots(SSLContextRef context, Boolean allowsExpiredRoots) {
    (void)context;
    (void)allowsExpiredRoots;
    return noErr;
}

static inline OSStatus SSLSetAllowsExpiredCerts(SSLContextRef context, Boolean allowsExpiredCerts) {
    (void)context;
    (void)allowsExpiredCerts;
    return noErr;
}

static inline OSStatus SSLSetEnableCertVerify(SSLContextRef context, Boolean enableVerify) {
    (void)context;
    (void)enableVerify;
    return noErr;
}

static inline OSStatus SSLSetProtocolVersionMin(SSLContextRef context, SSLProtocol protocol) {
    (void)context;
    (void)protocol;
    return noErr;
}

static inline OSStatus SSLSetProtocolVersionMax(SSLContextRef context, SSLProtocol protocol) {
    (void)context;
    (void)protocol;
    return noErr;
}

static inline OSStatus SSLSetProtocolVersionMinMax(SSLContextRef context, SSLProtocol minVersion, SSLProtocol maxVersion) {
    (void)context;
    (void)minVersion;
    (void)maxVersion;
    return noErr;
}

static inline OSStatus SSLSetProtocolVersionEnabled(SSLContextRef context, SSLProtocol protocol, Boolean enabled) {
    (void)context;
    (void)protocol;
    (void)enabled;
    return noErr;
}

static inline OSStatus SSLSetEnabledCiphers(SSLContextRef context, const SSLCipherSuite *ciphers, size_t numCiphers) {
    (void)context;
    (void)ciphers;
    (void)numCiphers;
    return noErr;
}

static inline OSStatus SSLSetDiffieHellmanParams(SSLContextRef context, const void *params, size_t paramsLen) {
    (void)context;
    (void)params;
    (void)paramsLen;
    return noErr;
}

static inline OSStatus SSLHandshake(SSLContextRef context) {
    (void)context;
    return noErr;
}

static inline OSStatus SSLRead(SSLContextRef context, void *data, size_t dataLength, size_t *processed) {
    (void)context;
    (void)data;
    (void)dataLength;
    if (processed != NULL) {
        *processed = 0;
    }
    return errSSLWouldBlock;
}

static inline OSStatus SSLWrite(SSLContextRef context, const void *data, size_t dataLength, size_t *processed) {
    (void)context;
    (void)data;
    (void)dataLength;
    if (processed != NULL) {
        *processed = 0;
    }
    return errSSLWouldBlock;
}

static inline OSStatus SSLGetBufferedReadSize(SSLContextRef context, size_t *bufferSize) {
    (void)context;
    if (bufferSize != NULL) {
        *bufferSize = 0;
    }
    return noErr;
}

#endif
