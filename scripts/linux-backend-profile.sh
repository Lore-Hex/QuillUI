#!/usr/bin/env bash
# Run a Quill app under Xvfb, sample startup time + RSS + CPU,
# and emit a CSV row to stdout. Used by Linux CI to surface a
# backend-neutral baseline profile per app so we can spot Linux-side regressions
# vs the macOS originals (e.g., a SwiftOpenUI render-loop hot
# path leaking, backend widget churn pushing RSS past sensible
# bounds).
#
# Two CPU samples are taken:
#   cpu_pct_initial  - 5s window starting at <settle>s after the
#                      first window appears. Catches the boot
#                      cost: fetch + decode + first render.
#   cpu_pct_steady   - 5s window starting at <settle> + <steady>
#                      seconds. Catches the long-term render-loop
#                      cost after the boot cost has finished.
#
# Usage:
#   scripts/linux-backend-profile.sh <product-name> [settle-seconds] [steady-delay]
#
# Emits one CSV line on stdout:
#   product,build_ms,startup_ms,rss_kb,cpu_pct_initial,cpu_pct_steady,exit_status

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/.qa"
source "$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh"
quillui_alias_backend_profile_env

PRODUCT="${1:-}"
SETTLE_SECONDS="${2:-${QUILLUI_BACKEND_PROFILE_SETTLE:-5}}"
STEADY_DELAY_SECONDS="${3:-${QUILLUI_BACKEND_PROFILE_STEADY:-20}}"

if [[ -z "$PRODUCT" ]]; then
    echo "Usage: $0 <product-name> [settle-seconds] [steady-delay]" >&2
    exit 64
fi

quillui_install_linux_backend_smoke_packages

sample_cpu_pct() {
    local pid="$1"
    top -b -d 1 -n 6 -p "$pid" 2>/dev/null \
        | awk -v pid="$pid" '
            $1 == pid { samples[++n] = $9 }
            END {
                if (n < 2) { print "-1"; exit }
                sum = 0
                for (i = 2; i <= n; i++) sum += samples[i]
                printf "%.1f\n", sum / (n - 1)
            }
        '
}

# Build or resolve the executable (timed). We don't include build cost in
# startup_ms - it's captured separately so dependency caches don't pollute the
# startup signal.
build_start_ms=$(date +%s%3N)
quillui_resolve_linux_backend_executable "$PRODUCT" exe >/dev/null 2>&1
build_end_ms=$(date +%s%3N)
build_ms=$((build_end_ms - build_start_ms))

if [[ ! -x "$exe" ]]; then
    echo "$PRODUCT,$build_ms,-1,-1,-1,-1,build-missing"
    exit 1
fi

reference_window_width=""
reference_window_height=""
hide_window_menubar_label=""
quillui_backend_reference_window_defaults \
    reference_window_width \
    reference_window_height \
    hide_window_menubar_label

display_id="$(quillui_normalize_x_display_id "${QUILLUI_BACKEND_PROFILE_DISPLAY:-95}")"
screen_size="$(quillui_backend_screen_size "$PRODUCT" "${QUILLUI_BACKEND_PROFILE_SCREEN_SIZE:-}" "1180x760x24" "$reference_window_width" "$reference_window_height")"
xvfb_pid=""

cleanup() {
    quillui_stop_process_if_running "${app_pid:-}"
    quillui_stop_process_if_running "${xvfb_pid:-}"
}
trap cleanup EXIT

if ! quillui_start_xvfb "$display_id" "$screen_size" /tmp/quillui-profile-xvfb.log xvfb_pid; then
    echo "$PRODUCT,$build_ms,-1,-1,-1,-1,xvfb-failed"
    exit 1
fi

startup_start_ms=$(date +%s%3N)
app_environment=()
quillui_append_backend_launch_environment app_environment "$PRODUCT" "$display_id"
quillui_append_quill_chat_reference_environment_if_needed \
    app_environment \
    "$PRODUCT" \
    "$OUTPUT_DIR" \
    "$reference_window_width" \
    "$reference_window_height" \
    "$hide_window_menubar_label"
env "${app_environment[@]}" "$exe" >/tmp/quillui-profile-app.log 2>&1 &
app_pid=$!

# Wait for the X11 window to actually appear - that's the
# "rendered first frame" signal, not just "process exists".
deadline_ms=$((startup_start_ms + 30000))
while :; do
    now_ms=$(date +%s%3N)
    if (( now_ms > deadline_ms )); then
        echo "$PRODUCT,$build_ms,-1,-1,-1,-1,startup-timeout"
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
    echo "$PRODUCT,$build_ms,$startup_ms,-1,-1,-1,died-during-settle"
    exit 1
fi

# RSS in KB from /proc/PID/status:VmRSS - actual resident memory.
rss_kb=$(awk '/^VmRSS:/ {print $2}' "/proc/$app_pid/status" 2>/dev/null || echo "-1")

# First CPU window: 5 seconds starting at <settle>. Captures the
# boot cost - initial fetch, JSON/XML decode, first-frame paint.
cpu_pct_initial=$(sample_cpu_pct "$app_pid")

if ! kill -0 "$app_pid" >/dev/null 2>&1; then
    echo "$PRODUCT,$build_ms,$startup_ms,$rss_kb,$cpu_pct_initial,-1,died-after-initial"
    exit 1
fi

# Wait further, then take a steady-state sample. If the app's
# render loop is correctly idle when nothing's happening, this
# should be near zero. If it stays pegged, something is busy-
# looping (the IceCubes / NetNewsWire 99-132% CPU outliers in
# the first baseline were on this signal - we want to know
# whether they cool down or stay hot).
sleep "$STEADY_DELAY_SECONDS"

if ! kill -0 "$app_pid" >/dev/null 2>&1; then
    echo "$PRODUCT,$build_ms,$startup_ms,$rss_kb,$cpu_pct_initial,-1,died-during-steady-wait"
    exit 1
fi

cpu_pct_steady=$(sample_cpu_pct "$app_pid")

echo "$PRODUCT,$build_ms,$startup_ms,$rss_kb,$cpu_pct_initial,$cpu_pct_steady,ok"
