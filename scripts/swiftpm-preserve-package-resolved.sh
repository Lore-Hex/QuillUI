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

# Cap SwiftPM build parallelism to avoid OOM-induced "Corrupted JSON" failures.
#
# `swift build`/`swift test` default to -j$(nproc) (=4 on the 16 GiB ubuntu-24.04
# CI runner). Compiling the large generated SwiftUI app (and the full package +
# test targets) at full parallelism spikes past available memory; the OOM killer
# truncates a compiler frontend mid-write, after which SwiftPM aborts with
#   Internal Error: dataCorrupted(... "Corrupted JSON" ... unexpected end of file)
# Bounding the concurrent-frontend count keeps peak memory in check. This wrapper
# is the shared chokepoint every GTK/Qt swift build/test is routed through, so the
# cap is applied here once rather than at each call site.
#
# Linux-only by default (skipped where /proc/meminfo is absent, e.g. macOS). An
# explicit --jobs/-j on the command line always wins. Overridable via
# QUILLUI_SWIFT_JOBS (a number forces that count on any platform; "0"/"off"
# disables injection entirely).
RUN_CMD=("$@")
maybe_cap_swift_jobs() {
  [[ "${RUN_CMD[0]:-}" == "swift" ]] || return 0
  case "${RUN_CMD[1]:-}" in
    build|test) ;;
    *) return 0 ;;
  esac

  local arg
  for arg in "${RUN_CMD[@]}"; do
    case "$arg" in
      --jobs|--jobs=*|-j|-j[0-9]*) return 0 ;;
    esac
  done

  local jobs="${QUILLUI_SWIFT_JOBS:-}"
  if [[ "$jobs" == "0" || "$jobs" == "off" ]]; then
    return 0
  fi
  if [[ -z "$jobs" ]]; then
    [[ -r /proc/meminfo ]] || return 0
    local mem_kib ncpu mem_cap
    mem_kib="$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo 2>/dev/null || echo 0)"
    ncpu="$(nproc 2>/dev/null || echo 2)"
    # ~6 GiB of headroom per concurrent swift frontend, never above the CPU count.
    mem_cap=$(( mem_kib / (6 * 1024 * 1024) ))
    (( mem_cap < 1 )) && mem_cap=1
    jobs=$mem_cap
    (( jobs > ncpu )) && jobs=$ncpu
  fi
  [[ "$jobs" =~ ^[0-9]+$ ]] || return 0
  (( jobs < 1 )) && return 0

  RUN_CMD=("${RUN_CMD[0]}" "${RUN_CMD[1]}" --jobs "$jobs" "${RUN_CMD[@]:2}")
  echo "swiftpm-preserve-package-resolved: capping '${RUN_CMD[0]} ${RUN_CMD[1]}' to --jobs $jobs" >&2
}
maybe_cap_swift_jobs

set +e
(
  cd "$RUN_DIR"
  "${RUN_CMD[@]}"
)
status=$?
set -e

restore_package_resolved
trap - EXIT
exit "$status"
