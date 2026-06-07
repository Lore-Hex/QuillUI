#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat >&2 <<'MSG'
Usage: run-linux-backend-interaction-modes.sh OUTPUT_TEMPLATE PRODUCT BACKEND MODE...

Runs scripts/linux-backend-interaction-check.sh once per MODE with a per-mode
timeout. OUTPUT_TEMPLATE may include {product}, {backend}, and must include
{mode}. The app log path comes from QUILLUI_BACKEND_INTERACTION_APP_LOG_TEMPLATE
and defaults to .qa/{product}-interaction-{mode}.log.

Environment:
  QUILLUI_BACKEND_INTERACTION_MODE_TIMEOUT       Per-mode timeout, default 120s.
  QUILLUI_BACKEND_INTERACTION_MODE_KILL_AFTER   Grace period after timeout, default 15s.
  QUILLUI_BACKEND_INTERACTION_APP_LOG_TEMPLATE  Per-mode log path template.
MSG
}

replace_tokens() {
  local template="$1"
  local product="$2"
  local backend="$3"
  local mode="$4"
  local value="$template"
  value="${value//\{product\}/$product}"
  value="${value//\{backend\}/$backend}"
  value="${value//\{mode\}/$mode}"
  printf '%s\n' "$value"
}

if [[ $# -lt 4 ]]; then
  usage
  exit 64
fi

OUTPUT_TEMPLATE="$1"
PRODUCT="$2"
BACKEND="$3"
shift 3

if [[ "$OUTPUT_TEMPLATE" != *"{mode}"* ]]; then
  echo "OUTPUT_TEMPLATE must include {mode}: $OUTPUT_TEMPLATE" >&2
  usage
  exit 64
fi

MODE_TIMEOUT="${QUILLUI_BACKEND_INTERACTION_MODE_TIMEOUT:-120s}"
MODE_KILL_AFTER="${QUILLUI_BACKEND_INTERACTION_MODE_KILL_AFTER:-15s}"
APP_LOG_TEMPLATE="${QUILLUI_BACKEND_INTERACTION_APP_LOG_TEMPLATE:-.qa/{product}-interaction-{mode}.log}"

for mode in "$@"; do
  output_path="$(replace_tokens "$OUTPUT_TEMPLATE" "$PRODUCT" "$BACKEND" "$mode")"
  app_log_path="$(replace_tokens "$APP_LOG_TEMPLATE" "$PRODUCT" "$BACKEND" "$mode")"
  echo "==> Backend interaction mode: $PRODUCT ($BACKEND backend, $mode, timeout $MODE_TIMEOUT)"
  QUILLUI_BACKEND_INTERACTION_MODE="$mode" \
  QUILLUI_BACKEND_INTERACTION_APP_LOG="$app_log_path" \
    timeout --kill-after="$MODE_KILL_AFTER" "$MODE_TIMEOUT" \
      "$ROOT_DIR/scripts/linux-backend-interaction-check.sh" \
        "$output_path" \
        "$PRODUCT" \
        "$BACKEND"
done
