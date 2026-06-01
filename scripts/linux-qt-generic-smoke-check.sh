#!/usr/bin/env bash
set -euo pipefail

# linux-qt-generic-smoke-check.sh — build + render + verify the GENERIC
# SwiftUI→Qt backend smoke (BackendQt), in full isolation from the existing
# backend gate.
#
# This is the slice-2 wiring: it is the FIRST thing that compiles the CQtBridge
# C++ wrapper, links SwiftOpenUI into the Qt graph, and runs the real
# `QtBackend().run(QtSmokeApp.self)` SwiftUI tree under Xvfb. Everything here is
# deliberately self-contained so a failure can NEVER red the existing apps:
#
#   * It builds the `quill-qt-generic-smoke` product behind the opt-in
#     QUILLUI_QT_GENERIC=1 / QUILLUI_LINUX_BACKEND=qt manifest graph.
#   * It uses its OWN SwiftPM scratch path (.build-linux-qt-generic) so it cannot
#     disturb the shared .build-linux tree the canonical apps + smokes build in.
#   * It re-uses the SHARED screenshot verifier's existing
#     `validate_quill_backend_interaction_smoke` by passing the verify product
#     `quill-qt-generic-smoke-open` straight to verify-backend-screenshot.py —
#     no validator code is added or weakened for any existing product.
#
# It only borrows the pure Xvfb / window-find / capture helpers from
# quillui-linux-backend-smoke-lib.sh; it does NOT touch the shared product
# matrix, the smoke roster, or the existing check scripts.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/.qa"
SCREENSHOT_PATH="${1:-$OUTPUT_DIR/quill-qt-generic-smoke.png}"
PRODUCT="quill-qt-generic-smoke"
VERIFY_PRODUCT="quill-qt-generic-smoke-open"
# Dedicated scratch: the generic Qt graph re-adds SwiftOpenUI + its dependency
# checkouts, which must not perturb the canonical apps' .build-linux tree.
SCRATCH_PATH="${QUILLUI_QT_GENERIC_SCRATCH_PATH:-$ROOT_DIR/.build-linux-qt-generic}"
APP_LOG_PATH="${QUILLUI_QT_GENERIC_APP_LOG:-/tmp/quillui-qt-generic-smoke-app.log}"

source "$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh"

quillui_install_linux_backend_smoke_packages

mkdir -p "$(dirname "$SCREENSHOT_PATH")"

# The generic Qt build links SwiftOpenUI's cross-platform core and its Swift
# dependency graph (swift-dependencies, swift-sharing, GRDB, …). Those packages
# need the same Linux source-compat rewrites the GTK build applies (canImport
# fallbacks, os_unfair_lock → NSRecursiveLock, etc.). patch-swiftopenui-gtk-css.sh
# is idempotent and operates on this scratch's checkouts, so running it here makes
# the SwiftOpenUI graph compile under the Qt manifest too. It first resolves the
# package (with QUILLUI_QT_GENERIC set) so the SwiftOpenUI checkout exists.
echo "==> Preparing SwiftOpenUI Linux sources for the generic Qt graph ($SCRATCH_PATH)"
QUILLUI_LINUX_BACKEND=qt QUILLUI_QT_GENERIC=1 \
  "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" \
  swift package resolve --scratch-path "$SCRATCH_PATH"
QUILLUI_LINUX_BACKEND=qt QUILLUI_QT_GENERIC=1 \
  "$ROOT_DIR/scripts/patch-swiftopenui-gtk-css.sh" "$SCRATCH_PATH"

echo "==> Building $PRODUCT (QUILLUI_LINUX_BACKEND=qt, QUILLUI_QT_GENERIC=1)"
QUILLUI_LINUX_BACKEND=qt QUILLUI_QT_GENERIC=1 \
  "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" \
  swift build --scratch-path "$SCRATCH_PATH" --product "$PRODUCT"

BIN_DIR="$(
  QUILLUI_LINUX_BACKEND=qt QUILLUI_QT_GENERIC=1 \
    "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" \
    swift build --scratch-path "$SCRATCH_PATH" --show-bin-path
)"
APP_EXECUTABLE="$BIN_DIR/$PRODUCT"

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "Built executable is missing or not executable: $APP_EXECUTABLE" >&2
  exit 1
fi

if ! command -v xdotool >/dev/null 2>&1; then
  echo "xdotool is required for the generic Qt backend smoke" >&2
  exit 69
fi

DISPLAY_ID="$(quillui_normalize_x_display_id "${QUILLUI_QT_GENERIC_DISPLAY:-:96}")"
SCREEN_SIZE="${QUILLUI_QT_GENERIC_SCREEN_SIZE:-1180x900x24}"
xvfb_pid=""
quillui_start_xvfb "$DISPLAY_ID" "$SCREEN_SIZE" /tmp/quillui-xvfb-qt-generic.log xvfb_pid

app_pid=""
cleanup() {
  quillui_stop_process_if_running "${app_pid:-}"
  quillui_stop_process_if_running "$xvfb_pid"
}
trap cleanup EXIT

# Launch with the same minimal environment the per-app Qt smokes use: DISPLAY
# under Xvfb (Qt6 defaults to the xcb platform plugin when DISPLAY is set) plus
# GTK_A11Y=none. No QT_QPA_PLATFORM override — mirror the existing Qt launches.
GTK_A11Y=none DISPLAY="$DISPLAY_ID" \
  "$APP_EXECUTABLE" >"$APP_LOG_PATH" 2>&1 &
app_pid=$!

sleep 4

capture_window="root"
window_id="$(quillui_find_visible_window_for_pid "$DISPLAY_ID" "$app_pid")"
if [[ -z "$window_id" ]]; then
  window_id="$(quillui_find_visible_window_by_name "$DISPLAY_ID" ".*")"
fi
if [[ -n "$window_id" ]]; then
  quillui_move_window_to_origin "$DISPLAY_ID" "$window_id"
  capture_window="$window_id"
fi

DISPLAY="$DISPLAY_ID" import -window "$capture_window" "$SCREENSHOT_PATH"

if "$ROOT_DIR/scripts/verify-backend-screenshot.py" "$SCREENSHOT_PATH" "$VERIFY_PRODUCT"; then
  :
else
  verify_status=$?
  quillui_print_backend_app_log_tail "$APP_LOG_PATH" "${QUILLUI_QT_GENERIC_APP_LOG_LINES:-120}"
  exit "$verify_status"
fi
