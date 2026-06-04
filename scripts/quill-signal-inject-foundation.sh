#!/usr/bin/env bash
#
# QuillSignal upstream-prepare pipeline step: inject `import Foundation` into
# SignalServiceKit Swift sources that use Foundation types but do not import it.
#
# On Apple, the SignalServiceKit umbrella (SignalServiceKit-Swift.h / the ObjC
# bridging header) makes Foundation implicitly available to every Swift file in
# the module. On Linux + SwiftPM there is no umbrella, so each file must `import
# Foundation` itself. Many upstream files rely on the implicit import (they only
# `import GRDB` / `import LibSignalClient` / `import CryptoKit`, none of which
# re-export Foundation on Linux), producing thousands of "cannot find type
# 'Date'/'Data'/'DispatchQueue'/'TimeInterval'/'URLRequest'" errors.
#
# This step is idempotent and disposable-tree-only: it mutates the gitignored
# .upstream checkout in place (like the lowering pass), so the SCRIPT is the
# durable, committed artifact. Run after fetch + quill-lower-appkit.
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
FOUNDATION_TYPES='DispatchQueue|DispatchTime|DispatchGroup|TimeInterval|URLRequest|URLSession|URLComponents|\bURL\b|FileManager|FileHandle|NotificationCenter|\bNotification\b|\bData\b|\bDate\b|DateComponents|DateFormatter|\bUUID\b|IndexSet|\bCalendar\b|\bLocale\b|TimeZone|\bData\(|\bNSObject\b|NSNumber|NSString|NSData|NSDate|NSError|NSRange|NSRegularExpression|JSONDecoder|JSONEncoder|JSONSerialization|PropertyListDecoder|OperationQueue|\bOperation\b|ProcessInfo|\bBundle\b|\bScanner\b|CharacterSet|\bPipe\b'

injected=0
scanned=0

while IFS= read -r f; do
    scanned=$((scanned + 1))
    # Already imports Foundation (directly)? skip.
    if grep -qE '^[[:space:]]*(public |@_exported )?import Foundation\b' "$f"; then
        continue
    fi
    # Does not actually use a Foundation type? skip.
    if ! grep -qE "$FOUNDATION_TYPES" "$f"; then
        continue
    fi
    # Prepend `import Foundation`. Swift permits an import before the leading
    # copyright comment, so a simple prepend is always valid.
    printf 'import Foundation\n' | cat - "$f" > "$f.qfimport.tmp"
    mv "$f.qfimport.tmp" "$f"
    injected=$((injected + 1))
done < <(find "$ROOT" -name '*.swift' -not -path '*/QuillPort/*')

echo "quill-signal-inject-foundation: scanned $scanned .swift, injected import Foundation into $injected"
