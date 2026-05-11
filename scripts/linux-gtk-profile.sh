#!/usr/bin/env bash
# Run a Quill app under Xvfb, sample startup time + RSS + CPU,
# and emit a CSV row to stdout. Used by Linux CI to surface a
# baseline profile per app so we can spot Linux-side regressions
# vs the macOS originals (e.g., a SwiftOpenUI render-loop hot
# path leaking, GTK widget churn pushing RSS past sensible
# bounds).
#
# Usage:
#   scripts/linux-gtk-profile.sh <product-name> [settle-seconds]
#
# Emits one CSV line on stdout:
#   product,build_ms,startup_ms,rss_kb,cpu_pct_5s,exit_status

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCT="${1:-}"
SETTLE_SECONDS="${2:-${QUILLUI_GTK_PROFILE_SETTLE:-5}}"

if [[ -z "$PRODUCT" ]]; then
    echo "Usage: $0 <product-name> [settle-seconds]" >&2
    exit 64
fi

# Build (timed). We don't include build cost in startup_ms — it's
# captured separately so dependency caches don't pollute the
# startup signal.
build_start_ms=$(date +%s%3N)
"$ROOT_DIR/scripts/patch-swiftopenui-gtk-css.sh" "$ROOT_DIR/.build-linux" >/dev/null 2>&1 || true
swift build --scratch-path "$ROOT_DIR/.build-linux" --product "$PRODUCT" >/dev/null 2>&1
build_end_ms=$(date +%s%3N)
build_ms=$((build_end_ms - build_start_ms))

bin_path="$(swift build --scratch-path "$ROOT_DIR/.build-linux" --show-bin-path)"
exe="$bin_path/$PRODUCT"
if [[ ! -x "$exe" ]]; then
    echo "$PRODUCT,$build_ms,-1,-1,-1,build-missing"
    exit 1
fi

display_id=":${QUILLUI_GTK_PROFILE_DISPLAY:-95}"
screen_size="${QUILLUI_GTK_PROFILE_SCREEN_SIZE:-1180x760x24}"
Xvfb "$display_id" -screen 0 "$screen_size" >/tmp/quillui-profile-xvfb.log 2>&1 &
xvfb_pid=$!

cleanup() {
    if [[ -n "${app_pid:-}" ]]; then kill "$app_pid" >/dev/null 2>&1 || true; fi
    kill "$xvfb_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT

sleep 1
if ! kill -0 "$xvfb_pid" >/dev/null 2>&1; then
    echo "$PRODUCT,$build_ms,-1,-1,-1,xvfb-failed"
    exit 1
fi

startup_start_ms=$(date +%s%3N)
GTK_A11Y=none DISPLAY="$display_id" "$exe" >/tmp/quillui-profile-app.log 2>&1 &
app_pid=$!

# Wait for the X11 window to actually appear — that's the
# "rendered first frame" signal, not just "process exists".
deadline_ms=$((startup_start_ms + 30000))
while :; do
    now_ms=$(date +%s%3N)
    if (( now_ms > deadline_ms )); then
        echo "$PRODUCT,$build_ms,-1,-1,-1,startup-timeout"
        exit 1
    fi
    if DISPLAY="$display_id" xdotool search --onlyvisible "" 2>/dev/null | head -n 1 | grep -q .; then
        break
    fi
    sleep 0.05
done
startup_end_ms=$(date +%s%3N)
startup_ms=$((startup_end_ms - startup_start_ms))

# Let the app settle (animations, font caches, etc.) then sample.
sleep "$SETTLE_SECONDS"

if ! kill -0 "$app_pid" >/dev/null 2>&1; then
    echo "$PRODUCT,$build_ms,$startup_ms,-1,-1,died-during-settle"
    exit 1
fi

# RSS in KB from /proc/PID/status:VmRSS — actual resident memory.
rss_kb=$(awk '/^VmRSS:/ {print $2}' "/proc/$app_pid/status" 2>/dev/null || echo "-1")

# CPU percent over a 5s window via top in batch mode. -d 1 -n 6
# gives us 6 samples (first is initial, next 5 are deltas); we
# average the 5 deltas. -p restricts to our PID; -b is batch
# (non-interactive); -n is sample count.
cpu_pct_5s=$(
    top -b -d 1 -n 6 -p "$app_pid" 2>/dev/null \
        | awk -v pid="$app_pid" '
            $1 == pid { samples[++n] = $9 }
            END {
                if (n < 2) { print "-1"; exit }
                sum = 0
                for (i = 2; i <= n; i++) sum += samples[i]
                printf "%.1f\n", sum / (n - 1)
            }
        '
)

echo "$PRODUCT,$build_ms,$startup_ms,$rss_kb,$cpu_pct_5s,ok"
