#!/usr/bin/env bash
#
# Measure the current Linux compile state of Signal's prepared app target.
# This is intentionally a host-side Docker wrapper because the macOS host does
# not have the Linux Swift toolchain. The default build volume is the renderer
# product cache, which is known to contain OpenCombine's C helper module; older
# scratch volumes may fail before reaching Signal with "missing required module
# 'COpenCombineHelpers'".
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${QUILL_SIGNAL_DOCKER_IMAGE:-quillui-signal-build}"
BUILD_VOLUME="${QUILL_SIGNAL_BUILD_VOLUME:-quillui-signal-product-clean}"
LOG="${QUILL_SIGNAL_APP_LOG:-$ROOT/.signalapp-target.log}"

docker run --rm \
    -v "$ROOT:/qui" \
    -v "$BUILD_VOLUME:/qui/.build" \
    "$IMAGE" \
    bash -lc 'cd /qui && QUILLUI_LINUX_BACKEND=gtk swift build --disable-index-store --jobs 1 --target SignalApp 2>&1' \
    >"$LOG" 2>&1 || true

unique_errors="$(
    (grep -oE '/qui/[^ ]+\.swift:[0-9]+:[0-9]+: error:' "$LOG" || true) \
        | sort -u \
        | wc -l \
        | tr -d ' '
)"

echo "SignalApp unique source-error locations: $unique_errors"
echo "Build log: $LOG"

if grep -q "missing required module 'COpenCombineHelpers'" "$LOG"; then
    cat <<MSG
Dependency cache failure: OpenCombine's C helper module is missing from build volume '$BUILD_VOLUME'.
Retry with QUILL_SIGNAL_BUILD_VOLUME=quillui-signal-product-clean, or rebuild the stale volume.
MSG
    exit 2
fi

if grep -q "Build of target: 'SignalApp' complete!" "$LOG"; then
    echo "SignalApp target build: clean"
    exit 0
fi

echo "Top error categories:"
(grep -oE ': error: .*' "$LOG" || true) \
    | sed -E "s/'[^']*'/'X'/g; s/[0-9]+/N/g" \
    | sort \
    | uniq -c \
    | sort -rn \
    | head -20

exit 1
