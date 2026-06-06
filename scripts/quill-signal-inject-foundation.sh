#!/usr/bin/env bash
#
# QuillSignal upstream-prepare pipeline step: inject the implicit umbrella
# imports (`Foundation`, `UIKit`) into SignalServiceKit Swift sources that use
# those frameworks' types but do not import them.
#
# On Apple, the SignalServiceKit umbrella (SignalServiceKit-Swift.h / the ObjC
# bridging header) makes Foundation (and, for the iOS build, UIKit) implicitly
# available to every Swift file in the module. On Linux + SwiftPM there is no
# umbrella, so each file must import them itself. Many upstream files rely on the
# implicit import (they only `import GRDB` / `import LibSignalClient` / etc., none
# of which re-export Foundation or UIKit on Linux), producing thousands of
# "cannot find type 'Date'/'Data'/'DispatchQueue'/'UIColor'/'UIImage'/…" errors.
#
# This step is idempotent and disposable-tree-only: it mutates the gitignored
# .upstream checkout in place (like the lowering pass), so the SCRIPT is the
# durable, committed artifact. Run after fetch + quill-lower-appkit.
#
# On Linux, `UIKit` resolves to the QuillUIKit shim target (an SSK dependency).
#
# Usage: scripts/quill-signal-inject-foundation.sh [SSK_ROOT]
#   SSK_ROOT defaults to .upstream/signal-ios/SignalServiceKit
#
set -euo pipefail

ROOT="${1:-.upstream/signal-ios/SignalServiceKit}"

if [ ! -d "$ROOT" ]; then
    echo "error: SSK root not found: $ROOT" >&2
    exit 1
fi

# Foundation types whose presence means the file needs `import Foundation`.
# Word-boundaried so e.g. Data does not match Database / DataMessage.
FOUNDATION_TYPES='DispatchQueue|DispatchTime|DispatchGroup|TimeInterval|URLRequest|URLSession|URLComponents|\bURL\b|FileManager|FileHandle|NotificationCenter|\bNotification\b|\bData\b|\bDate\b|DateComponents|DateFormatter|\bUUID\b|IndexSet|\bCalendar\b|\bLocale\b|TimeZone|\bData\(|\bNSObject\b|NSNumber|NSString|NSData|NSDate|NSError|NSRange|NSRegularExpression|JSONDecoder|JSONEncoder|JSONSerialization|PropertyListDecoder|OperationQueue|\bOperation\b|ProcessInfo|\bBundle\b|\bScanner\b|CharacterSet|\bPipe\b|\bCGFloat\b|\bCGSize\b|\bCGRect\b|\bCGPoint\b|\bCGVector\b|\bCGAffineTransform\b|\bNSAttributedString\b|\bNSMutableAttributedString\b'

# UIKit types (resolved via the QuillUIKit shim on Linux).
UIKIT_TYPES='\bUIColor\b|\bUIImage\b|\bUIFont\b|\bUIView\b|\bUIApplication\b|\bUIDevice\b|\bUIScreen\b|\bUIViewController\b|\bUIPasteboard\b|\bUIImpactFeedbackGenerator\b|\bUISelectionFeedbackGenerator\b|\bUINotificationFeedbackGenerator\b|\bUIBezierPath\b|\bUIEdgeInsets\b|\bUIInterfaceOrientation\b|\bUIBackgroundTaskIdentifier\b|\bUIActivityViewController\b|\bNSTextAlignment\b|\bUISwitch\b|\bUIDeviceOrientation\b'

# Networking types that, on Linux/swift-corelibs-foundation, live in the separate
# FoundationNetworking module (on Apple they are part of Foundation). The injected
# import is canImport-gated so it is a no-op on Apple.
FOUNDATIONNETWORKING_TYPES='\bURLRequest\b|\bURLResponse\b|\bHTTPURLResponse\b|\bURLSession\b|\bURLSessionTask\b|\bURLSessionDataTask\b|\bURLSessionUploadTask\b|\bURLSessionDownloadTask\b|\bURLSessionWebSocketTask\b|\bURLSessionConfiguration\b|\bURLSessionDelegate\b|\bURLSessionTaskDelegate\b|\bURLSessionDataDelegate\b|\bURLSessionWebSocketDelegate\b|\bURLAuthenticationChallenge\b|\bURLCredential\b|\bURLProtocol\b|\bURLProtectionSpace\b|\bHTTPCookie\b|\bURLCache\b|\bCachedURLResponse\b'

# ImageIO: CGImageSource and the kCGImage* metadata keys (the ImageIO shim on
# Linux). On Apple these arrive transitively via UIKit / CoreGraphics, so the
# upstream files do not import ImageIO explicitly.
IMAGEIO_TYPES='\bCGImageSource\b|\bkCGImage'

# CoreFoundation: the CF* value types. swift-corelibs-foundation's `import
# Foundation` does not re-export these on Linux (on Apple it does), so files
# using a bare `CFDictionary`/`CFData`/... (often only in an `as CFDictionary`
# cast) fail with "cannot find type". An explicit `import CoreFoundation` (a
# real module on both Apple and Linux) resolves them.
COREFOUNDATION_TYPES='\bCFData\b|\bCFString\b|\bCFDictionary\b|\bCFArray\b|\bCFNumber\b|\bCFBoolean\b|\bCFURL\b|\bCFTypeRef\b|\bCFType\b|\bCFIndex\b|\bCFError\b|\bCFRange\b|\bCFMutable[A-Za-z]+\b|\bCFAllocator|\bCFTimeInterval\b|\bCFAbsoluteTime\b'

# QuartzCore: CACurrentMediaTime (monotonic timing) and the CA* layer / display
# -link types (the QuartzCore shim on Linux). On Apple these arrive transitively
# via UIKit, so the upstream files do not import QuartzCore explicitly.
QUARTZCORE_TYPES='\bCACurrentMediaTime\b|\bCADisplayLink\b|\bCAGradientLayer\b|\bCALayer\b|\bCAShapeLayer\b|\bCAMediaTimingFunction\b|\bCATransaction\b|\bCAAnimation\b'

# Security: the Keychain / SecTrust / SecKey / SecRandom API (the Security shim on
# Linux). On Apple these arrive via the bridging umbrella; on Linux each file that
# uses them must `import Security`. Matches Sec<Uppercase> (SecKey/SecTrust/SecItem*
# /SecCertificate/...), errSec* status codes, and kSec* dictionary keys.
SECURITY_TYPES='\bSec[A-Z][A-Za-z]+|\berrSec[A-Za-z]+|\bkSec[A-Za-z]+'

# CFNetwork: the system-proxy lookup (the CFNetwork shim on Linux). NetworkManager
# reads kCFProxy* + CFNetworkCopySystemProxySettings/CFNetworkCopyProxiesForURL but
# imports only CoreFoundation/Foundation on Apple (CFNetwork arrives via the
# umbrella). On Linux it needs an explicit `import CFNetwork`.
CFNETWORK_TYPES='\bkCFProxy[A-Za-z]+|\bCFNetworkCopy[A-Za-z]+'

# Symbols QuillFoundation provides (Linux-gated) but swift-corelibs does NOT,
# used by files importing only Foundation -> they need an explicit
# `import QuillFoundation`: the Darwin time-scale constants (NSEC_PER_SEC etc,
# from <mach/clock_types.h>) and NSHashTable (the weak-collection shim, e.g.
# MessagePipelineSupervisor).
TIMECONST_TYPES='\bNSEC_PER_SEC\b|\bNSEC_PER_MSEC\b|\bNSEC_PER_USEC\b|\bMSEC_PER_SEC\b|\bUSEC_PER_SEC\b|\bNSHashTable\b'

# Raw sqlite3 C API (SQLITE_OK / sqlite3_errmsg / sqlite3_step ...): ~12 SSK files
# drop to the C API under GRDB. On Apple these come via the bridging header; on
# Linux GRDB vends them through its GRDBSQLite system-library module.
SQLITE_TYPES='\bSQLITE_[A-Z][A-Z0-9_]*\b|\bsqlite3_[a-z][a-z0-9_]*\b'

injected=0
scanned=0

inject_if_needed() {
    # $1 file, $2 module name, $3 type-regex
    local f="$1" module="$2" types="$3"
    grep -qE "^[[:space:]]*(public |@_exported )?import ${module}\b" "$f" && return 1
    grep -qE "$types" "$f" || return 1
    # Prepend `import <module>`. Swift permits an import before the leading
    # copyright comment, so a simple prepend is always valid.
    printf 'import %s\n' "$module" | cat - "$f" > "$f.qfimport.tmp"
    mv "$f.qfimport.tmp" "$f"
    return 0
}

inject_gated_if_needed() {
    # $1 file, $2 module name, $3 type-regex — prepends a canImport-gated import.
    local f="$1" module="$2" types="$3"
    grep -qE "import ${module}\b" "$f" && return 1
    grep -qE "$types" "$f" || return 1
    {
        printf '#if canImport(%s)\nimport %s\n#endif\n' "$module" "$module"
        cat "$f"
    } > "$f.qfimport.tmp"
    mv "$f.qfimport.tmp" "$f"
    return 0
}

while IFS= read -r f; do
    scanned=$((scanned + 1))
    touched=0
    if inject_if_needed "$f" "Foundation" "$FOUNDATION_TYPES"; then touched=1; fi
    if inject_if_needed "$f" "UIKit" "$UIKIT_TYPES"; then touched=1; fi
    if inject_if_needed "$f" "ImageIO" "$IMAGEIO_TYPES"; then touched=1; fi
    # CoreFoundation: SKIP (and strip any prior injection) for files that use
    # Security. Security @_exported-imports QuillKit, whose lightweight CF*
    # typealiases (CFDictionary=[String:Any], CFArray=[Any], CFTypeRef=AnyObject,
    # CFString=String, CFData=Data) would otherwise be AMBIGUOUS with
    # swift-corelibs CoreFoundation's opaque CF types ("CFDictionary is ambiguous
    # for type lookup"). Verified: the Security-using SSK files reference only CF
    # *types*, never real CF *functions* (CFArrayCreate/etc), so the QuillKit
    # typealiases fully suffice. The strip is needed because inject is add-only.
    if grep -qE "^import Security\b" "$f" || grep -qE "$SECURITY_TYPES" "$f"; then
        if grep -qE "^import CoreFoundation\b" "$f"; then
            grep -vE "^import CoreFoundation\b" "$f" > "$f.qfcf.tmp" && mv "$f.qfcf.tmp" "$f"
            touched=1
        fi
    else
        if inject_if_needed "$f" "CoreFoundation" "$COREFOUNDATION_TYPES"; then touched=1; fi
    fi
    if inject_if_needed "$f" "QuartzCore" "$QUARTZCORE_TYPES"; then touched=1; fi
    if inject_if_needed "$f" "Security" "$SECURITY_TYPES"; then touched=1; fi
    if inject_if_needed "$f" "CFNetwork" "$CFNETWORK_TYPES"; then touched=1; fi
    if inject_if_needed "$f" "QuillFoundation" "$TIMECONST_TYPES"; then touched=1; fi
    if inject_if_needed "$f" "GRDBSQLite" "$SQLITE_TYPES"; then touched=1; fi
    if inject_gated_if_needed "$f" "FoundationNetworking" "$FOUNDATIONNETWORKING_TYPES"; then touched=1; fi
    injected=$((injected + touched))
done < <(find "$ROOT" -name '*.swift' -not -path '*/QuillPort/*')

echo "quill-signal-inject-foundation: scanned $scanned .swift, injected import(s) into $injected files"
