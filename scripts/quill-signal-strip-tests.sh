#!/usr/bin/env bash
#
# QuillSignal upstream-prepare pipeline step: remove XCTest test files from the
# SignalServiceKit source tree.
#
# signalapp/Signal-iOS co-locates XCTest test files (and their mocks/helpers)
# inside the SignalServiceKit directory. On Apple these belong to a separate
# `SignalServiceKitTests` target; under our SwiftPM library target everything
# beneath the target `path` is compiled into the LIBRARY, so the tests (and
# test-only helpers like InMemoryDB) are dragged in and fail — they are not part
# of the product. This step deletes them from the disposable .upstream checkout.
#
# It removes any `.swift` file that `import`s XCTest (unambiguously a test), and
# is idempotent. The committed SCRIPT is the durable artifact; run after fetch.
#
# Usage: scripts/quill-signal-strip-tests.sh [SSK_ROOT]
#   SSK_ROOT defaults to .upstream/signal-ios/SignalServiceKit
#
set -euo pipefail

ROOT="${1:-.upstream/signal-ios/SignalServiceKit}"

if [ ! -d "$ROOT" ]; then
    echo "error: SSK root not found: $ROOT" >&2
    exit 1
fi

removed=0
while IFS= read -r f; do
    if grep -qE '^[[:space:]]*(@testable )?import XCTest\b' "$f"; then
        rm -f "$f"
        removed=$((removed + 1))
    fi
done < <(find "$ROOT" -name '*.swift' -not -path '*/QuillPort/*')

echo "quill-signal-strip-tests: removed $removed XCTest file(s)"
