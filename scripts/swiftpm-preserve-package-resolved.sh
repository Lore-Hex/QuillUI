#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CALLER_PWD="$PWD"

usage() {
  cat <<'USAGE'
Usage: scripts/swiftpm-preserve-package-resolved.sh COMMAND [ARG...]

Run a SwiftPM command while restoring Package.resolved afterward. Backend
manifest selection can temporarily prune pins from Package.resolved; this
wrapper keeps repeated GTK/Qt checks from leaving resolver churn in the
worktree.
USAGE
}

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 64
fi

PACKAGE_DIR="${QUILLUI_SWIFTPM_PACKAGE_PATH:-}"
previous_arg=""
for arg in "$@"; do
  if [[ "$previous_arg" == "--package-path" ]]; then
    PACKAGE_DIR="$arg"
    break
  fi

  case "$arg" in
    --package-path=*)
      PACKAGE_DIR="${arg#--package-path=}"
      break
      ;;
  esac

  previous_arg="$arg"
done

if [[ -z "$PACKAGE_DIR" ]]; then
  PACKAGE_DIR="$ROOT_DIR"
fi

case "$PACKAGE_DIR" in
  /*)
    ;;
  *)
    PACKAGE_DIR="$CALLER_PWD/$PACKAGE_DIR"
    ;;
esac

PACKAGE_RESOLVED="$PACKAGE_DIR/Package.resolved"
TEMP_RESOLVED=""
HAD_PACKAGE_RESOLVED=0
RESTORED_PACKAGE_RESOLVED=0

if [[ -f "$PACKAGE_RESOLVED" ]]; then
  HAD_PACKAGE_RESOLVED=1
  TEMP_RESOLVED="$(mktemp "${TMPDIR:-/tmp}/quillui-package-resolved.XXXXXX")"
  cp -p "$PACKAGE_RESOLVED" "$TEMP_RESOLVED"
fi

restore_package_resolved() {
  if [[ "$RESTORED_PACKAGE_RESOLVED" == "1" ]]; then
    return 0
  fi
  RESTORED_PACKAGE_RESOLVED=1

  if [[ "$HAD_PACKAGE_RESOLVED" == "1" ]]; then
    cp -p "$TEMP_RESOLVED" "$PACKAGE_RESOLVED"
    rm -f "$TEMP_RESOLVED"
  else
    rm -f "$PACKAGE_RESOLVED"
  fi
}

trap 'status=$?; restore_package_resolved; exit "$status"' EXIT

RUN_DIR="$CALLER_PWD"
if [[ -z "${QUILLUI_SWIFTPM_KEEP_CWD:-}" && "$PACKAGE_DIR" == "$ROOT_DIR" ]]; then
  RUN_DIR="$ROOT_DIR"
fi

set +e
(
  cd "$RUN_DIR"
  "$@"
)
status=$?
set -e

restore_package_resolved
trap - EXIT
exit "$status"
