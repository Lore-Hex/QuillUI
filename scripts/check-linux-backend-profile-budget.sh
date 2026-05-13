#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/quillui-backend-products.sh"
quillui_alias_backend_profile_env

MAX_CPU_PCT="${QUILLUI_BACKEND_PROFILE_MAX_CPU_PCT:-25}"
MAX_RSS_KB="${QUILLUI_BACKEND_PROFILE_MAX_RSS_KB:-300000}"
MAX_STARTUP_MS="${QUILLUI_BACKEND_PROFILE_MAX_STARTUP_MS:-5000}"
REQUIRE_BACKEND_MATRIX=0
CSV_PATH=""

usage() {
  echo "Usage: $(basename "$0") CSV [--max-cpu-pct N] [--max-rss-kb N] [--max-startup-ms N] [--require-backend-matrix]" >&2
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
    --require-backend-matrix)
      REQUIRE_BACKEND_MATRIX=1
      shift
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

if [[ "$REQUIRE_BACKEND_MATRIX" -eq 1 ]]; then
  actual_profile_rows=$'\n'
  while IFS=, read -r product requested_backend _; do
    [[ -n "$product" && "$product" != "product" ]] || continue
    actual_profile_rows="${actual_profile_rows}${product}@${requested_backend}"$'\n'
  done < "$CSV_PATH"

  missing_required_row=0
  while IFS=$'\t' read -r expected_product expected_backend; do
    [[ -n "$expected_product" && -n "$expected_backend" ]] || continue
    expected_backend="$(quillui_require_backend_identifier "$expected_backend")"
    expected_label="$expected_product@$expected_backend"
    case "$actual_profile_rows" in
      *$'\n'"$expected_label"$'\n'*)
        ;;
      *)
        echo "profile budget failed: missing required backend profile row: $expected_label" >&2
        missing_required_row=1
        ;;
    esac
  done < <(quillui_backend_profile_matrix)

  if [[ "$missing_required_row" -ne 0 ]]; then
    exit 1
  fi
fi

awk \
  -v max_cpu="$MAX_CPU_PCT" \
  -v max_rss="$MAX_RSS_KB" \
  -v max_startup="$MAX_STARTUP_MS" '
BEGIN {
  FS = ","
  status = 0
  expected = "product,requested_backend,runtime_backend,build_ms,startup_ms,rss_kb,cpu_pct_initial,cpu_pct_steady,exit_status"
}
function is_nonnegative_integer(value) {
  return value ~ /^[0-9]+$/
}
function is_nonnegative_number(value) {
  return value ~ /^[0-9]+([.][0-9]+)?$/
}
function is_backend_identifier(value) {
  return value ~ /^(swiftui|gtk|qt)$/
}
NR == 1 {
  if ($0 != expected) {
    printf "profile budget failed: unexpected header: %s\n", $0 > "/dev/stderr"
    status = 1
  }
  next
}
/^[[:space:]]*$/ { next }
NF != 9 {
  printf "profile budget failed: malformed row %d: %s\n", NR, $0 > "/dev/stderr"
  status = 1
  next
}
{
  product = $1
  requested_backend = $2
  runtime_backend = $3
  build_ms = $4
  startup_ms = $5
  rss_kb = $6
  cpu_initial = $7
  cpu_steady = $8
  exit_status = $9

  row_failed = 0
  if (product == "") {
    printf "profile budget failed: row %d has an empty product\n", NR > "/dev/stderr"
    row_failed = 1
  }
  if (!is_nonnegative_integer(build_ms)) {
    printf "profile budget failed: %s build_ms=%s is not a non-negative integer\n", product, build_ms > "/dev/stderr"
    row_failed = 1
  }
  if (!is_nonnegative_integer(startup_ms)) {
    printf "profile budget failed: %s startup_ms=%s is not a non-negative integer\n", product, startup_ms > "/dev/stderr"
    row_failed = 1
  }
  if (!is_nonnegative_integer(rss_kb)) {
    printf "profile budget failed: %s rss_kb=%s is not a non-negative integer\n", product, rss_kb > "/dev/stderr"
    row_failed = 1
  }
  if (!is_nonnegative_number(cpu_initial)) {
    printf "profile budget failed: %s cpu_pct_initial=%s is not a non-negative number\n", product, cpu_initial > "/dev/stderr"
    row_failed = 1
  }
  if (!is_nonnegative_number(cpu_steady)) {
    printf "profile budget failed: %s cpu_pct_steady=%s is not a non-negative number\n", product, cpu_steady > "/dev/stderr"
    row_failed = 1
  }
  if (exit_status != "ok") {
    printf "profile budget failed: %s exit_status=%s\n", product, exit_status > "/dev/stderr"
    row_failed = 1
  } else {
    if (!is_backend_identifier(requested_backend)) {
      printf "profile budget failed: %s requested_backend=%s is not supported\n", product, requested_backend > "/dev/stderr"
      row_failed = 1
    }
    if (!is_backend_identifier(runtime_backend)) {
      printf "profile budget failed: %s runtime_backend=%s is not supported\n", product, runtime_backend > "/dev/stderr"
      row_failed = 1
    }
  }

  if (row_failed) {
    status = 1
    next
  }

  startup_ms_value = startup_ms + 0
  rss_kb_value = rss_kb + 0
  cpu_initial_value = cpu_initial + 0
  cpu_steady_value = cpu_steady + 0

  if (startup_ms_value > max_startup) {
    printf "profile budget failed: %s startup_ms=%s max=%s\n", product, startup_ms, max_startup > "/dev/stderr"
    row_failed = 1
  }
  if (rss_kb_value > max_rss) {
    printf "profile budget failed: %s rss_kb=%s max=%s\n", product, rss_kb, max_rss > "/dev/stderr"
    row_failed = 1
  }
  if (cpu_initial_value > max_cpu) {
    printf "profile budget failed: %s cpu_pct_initial=%s max=%s\n", product, cpu_initial, max_cpu > "/dev/stderr"
    row_failed = 1
  }
  if (cpu_steady_value > max_cpu) {
    printf "profile budget failed: %s cpu_pct_steady=%s max=%s\n", product, cpu_steady, max_cpu > "/dev/stderr"
    row_failed = 1
  }

  if (row_failed) {
    status = 1
  } else {
    printf "profile budget ok: %s requested=%s runtime=%s startup_ms=%s rss_kb=%s cpu=%s/%s\n", product, requested_backend, runtime_backend, startup_ms, rss_kb, cpu_initial, cpu_steady
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
