#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/quillui-backend-products.sh"
quillui_alias_backend_profile_env

MAX_CPU_PCT="${QUILLUI_BACKEND_PROFILE_MAX_CPU_PCT:-25}"
MAX_RSS_KB="${QUILLUI_BACKEND_PROFILE_MAX_RSS_KB:-300000}"
MAX_STARTUP_MS="${QUILLUI_BACKEND_PROFILE_MAX_STARTUP_MS:-5000}"
CSV_PATH=""

usage() {
  echo "Usage: $(basename "$0") CSV [--max-cpu-pct N] [--max-rss-kb N] [--max-startup-ms N]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-cpu-pct)
      [[ $# -ge 2 && "${2:-}" != --* ]] || {
        echo "--max-cpu-pct requires a value" >&2
        usage
        exit 64
      }
      MAX_CPU_PCT="$2"
      shift 2
      ;;
    --max-rss-kb)
      [[ $# -ge 2 && "${2:-}" != --* ]] || {
        echo "--max-rss-kb requires a value" >&2
        usage
        exit 64
      }
      MAX_RSS_KB="$2"
      shift 2
      ;;
    --max-startup-ms)
      [[ $# -ge 2 && "${2:-}" != --* ]] || {
        echo "--max-startup-ms requires a value" >&2
        usage
        exit 64
      }
      MAX_STARTUP_MS="$2"
      shift 2
      ;;
    --help|-h) usage; exit 0 ;;
    --*) echo "Unknown argument: $1" >&2; usage; exit 64 ;;
    *)
      if [[ -n "$CSV_PATH" ]]; then
        echo "Only one CSV path is supported" >&2
        usage
        exit 64
      fi
      CSV_PATH="$1"
      shift
      ;;
  esac
done

if [[ -z "$CSV_PATH" ]]; then
  usage
  exit 64
fi

[[ "$MAX_CPU_PCT" =~ ^[0-9]+([.][0-9]+)?$ ]] || {
  echo "--max-cpu-pct must be a non-negative number, got: $MAX_CPU_PCT" >&2
  exit 64
}
[[ "$MAX_RSS_KB" =~ ^[1-9][0-9]*$ ]] || {
  echo "--max-rss-kb must be a positive integer, got: $MAX_RSS_KB" >&2
  exit 64
}
[[ "$MAX_STARTUP_MS" =~ ^[1-9][0-9]*$ ]] || {
  echo "--max-startup-ms must be a positive integer, got: $MAX_STARTUP_MS" >&2
  exit 64
}
[[ -f "$CSV_PATH" ]] || {
  echo "Profile CSV was not found: $CSV_PATH" >&2
  exit 66
}

awk \
  -v max_cpu="$MAX_CPU_PCT" \
  -v max_rss="$MAX_RSS_KB" \
  -v max_startup="$MAX_STARTUP_MS" '
BEGIN {
  FS = ","
  status = 0
  expected = "product,build_ms,startup_ms,rss_kb,cpu_pct_initial,cpu_pct_steady,exit_status"
}
function is_nonnegative_integer(value) {
  return value ~ /^[0-9]+$/
}
function is_nonnegative_number(value) {
  return value ~ /^[0-9]+([.][0-9]+)?$/
}
NR == 1 {
  if ($0 != expected) {
    printf "profile budget failed: unexpected header: %s\n", $0 > "/dev/stderr"
    status = 1
  }
  next
}
/^[[:space:]]*$/ { next }
NF != 7 {
  printf "profile budget failed: malformed row %d: %s\n", NR, $0 > "/dev/stderr"
  status = 1
  next
}
{
  product = $1
  exit_status = $7

  row_failed = 0
  if (product == "") {
    printf "profile budget failed: row %d has an empty product\n", NR > "/dev/stderr"
    row_failed = 1
  }
  if (!is_nonnegative_integer($2)) {
    printf "profile budget failed: %s build_ms=%s is not a non-negative integer\n", product, $2 > "/dev/stderr"
    row_failed = 1
  }
  if (!is_nonnegative_integer($3)) {
    printf "profile budget failed: %s startup_ms=%s is not a non-negative integer\n", product, $3 > "/dev/stderr"
    row_failed = 1
  }
  if (!is_nonnegative_integer($4)) {
    printf "profile budget failed: %s rss_kb=%s is not a non-negative integer\n", product, $4 > "/dev/stderr"
    row_failed = 1
  }
  if (!is_nonnegative_number($5)) {
    printf "profile budget failed: %s cpu_pct_initial=%s is not a non-negative number\n", product, $5 > "/dev/stderr"
    row_failed = 1
  }
  if (!is_nonnegative_number($6)) {
    printf "profile budget failed: %s cpu_pct_steady=%s is not a non-negative number\n", product, $6 > "/dev/stderr"
    row_failed = 1
  }
  if (exit_status != "ok") {
    printf "profile budget failed: %s exit_status=%s\n", product, exit_status > "/dev/stderr"
    row_failed = 1
  }

  if (row_failed) {
    status = 1
    next
  }

  startup_ms = $3 + 0
  rss_kb = $4 + 0
  cpu_initial = $5 + 0
  cpu_steady = $6 + 0

  if (startup_ms > max_startup) {
    printf "profile budget failed: %s startup_ms=%s max=%s\n", product, $3, max_startup > "/dev/stderr"
    row_failed = 1
  }
  if (rss_kb > max_rss) {
    printf "profile budget failed: %s rss_kb=%s max=%s\n", product, $4, max_rss > "/dev/stderr"
    row_failed = 1
  }
  if (cpu_initial > max_cpu) {
    printf "profile budget failed: %s cpu_pct_initial=%s max=%s\n", product, $5, max_cpu > "/dev/stderr"
    row_failed = 1
  }
  if (cpu_steady > max_cpu) {
    printf "profile budget failed: %s cpu_pct_steady=%s max=%s\n", product, $6, max_cpu > "/dev/stderr"
    row_failed = 1
  }

  if (row_failed) {
    status = 1
  } else {
    printf "profile budget ok: %s startup_ms=%s rss_kb=%s cpu=%s/%s\n", product, $3, $4, $5, $6
  }
}
END {
  if (NR < 2) {
    print "profile budget failed: no profile rows found" > "/dev/stderr"
    status = 1
  }
  exit status
}
' "$CSV_PATH"
