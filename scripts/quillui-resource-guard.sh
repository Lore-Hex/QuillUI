#!/usr/bin/env bash
set -euo pipefail

EXIT_RESOURCE_UNAVAILABLE=75

if [[ "${QUILLUI_RESOURCE_GUARD_DISABLE:-}" == "1" ]]; then
  echo "resource guard disabled by QUILLUI_RESOURCE_GUARD_DISABLE=1" >&2
  exit 0
fi

MIN_FREE_GIB="${QUILLUI_RESOURCE_GUARD_MIN_FREE_GIB:-12}"
MAX_USED_PERCENT="${QUILLUI_RESOURCE_GUARD_MAX_USED_PERCENT:-95}"
MIN_AVAILABLE_MEMORY_MIB="${QUILLUI_RESOURCE_GUARD_MIN_AVAILABLE_MEMORY_MIB:-2048}"
DIAGNOSTIC_PROCESS_LIMIT="${QUILLUI_RESOURCE_GUARD_DIAGNOSTIC_PROCESS_LIMIT:-8}"

fail_guard() {
  echo "resource guard failed: $1" >&2
  print_process_diagnostics || true
  exit "$EXIT_RESOURCE_UNAVAILABLE"
}

require_unsigned_integer() {
  local value="$1"
  local variable_name="$2"

  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    echo "$variable_name must be an unsigned integer, got: $value" >&2
    exit 64
  fi
}

available_memory_mib() {
  if [[ -r /proc/meminfo ]]; then
    awk '/^MemAvailable:/ { print int($2 / 1024); found = 1 } END { if (!found) exit 1 }' /proc/meminfo
    return
  fi

  if command -v vm_stat >/dev/null 2>&1; then
    local vm_output
    local page_size
    local pages_available

    vm_output="$(vm_stat)"
    page_size="$(
      awk '
        NR == 1 {
          for (field_index = 1; field_index <= NF; field_index += 1) {
            token = $field_index
            gsub(/[^0-9]/, "", token)
            if (token != "") {
              print token
              exit
            }
          }
        }
      ' <<<"$vm_output"
    )"
    pages_available="$(
      awk -F: '
        /^Pages free:/ || /^Pages speculative:/ || /^Pages purgeable:/ {
          value = $2
          gsub(/[^0-9]/, "", value)
          total += value
        }
        END { print total + 0 }
      ' <<<"$vm_output"
    )"

    if [[ -n "$page_size" && -n "$pages_available" ]]; then
      echo $((pages_available * page_size / 1024 / 1024))
      return
    fi
  fi

  return 1
}

print_process_diagnostics() {
  if (( DIAGNOSTIC_PROCESS_LIMIT == 0 )); then
    return 0
  fi

  command -v ps >/dev/null 2>&1 || return 0
  command -v sort >/dev/null 2>&1 || return 0
  command -v head >/dev/null 2>&1 || return 0
  command -v awk >/dev/null 2>&1 || return 0

  echo "resource guard diagnostics: top RSS processes (MiB)" >&2
  ps -axo pid=,rss=,command= 2>/dev/null |
    sort -nrk2 |
    head -n "$DIAGNOSTIC_PROCESS_LIMIT" |
    awk '
      {
        pid = $1
        rss_kib = $2
        $1 = ""
        $2 = ""
        sub(/^  */, "", $0)
        printf "  pid=%s rss=%dMiB command=%s\n", pid, int((rss_kib + 1023) / 1024), $0
      }
    ' >&2
}

check_disk_path() {
  local path="$1"
  local row
  local available_kib
  local used_percent
  local min_free_kib

  [[ -e "$path" ]] || fail_guard "disk path does not exist: $path"

  row="$(df -Pk "$path" | awk 'NR == 2 { gsub(/%/, "", $5); print $4 "\t" $5 }')"
  available_kib="${row%%$'\t'*}"
  used_percent="${row##*$'\t'}"
  min_free_kib=$((MIN_FREE_GIB * 1024 * 1024))

  if [[ -z "$available_kib" || -z "$used_percent" ]]; then
    fail_guard "could not read disk availability for $path"
  fi

  if (( available_kib < min_free_kib )); then
    fail_guard "$path has $((available_kib / 1024))MiB free; requires at least ${MIN_FREE_GIB}GiB"
  fi

  if (( used_percent >= MAX_USED_PERCENT )); then
    fail_guard "$path is ${used_percent}% full; maximum allowed is below ${MAX_USED_PERCENT}%"
  fi

  echo "resource guard ok: $path has $((available_kib / 1024))MiB free, ${used_percent}% used" >&2
}

require_unsigned_integer "$MIN_FREE_GIB" "QUILLUI_RESOURCE_GUARD_MIN_FREE_GIB"
require_unsigned_integer "$MAX_USED_PERCENT" "QUILLUI_RESOURCE_GUARD_MAX_USED_PERCENT"
require_unsigned_integer "$MIN_AVAILABLE_MEMORY_MIB" "QUILLUI_RESOURCE_GUARD_MIN_AVAILABLE_MEMORY_MIB"
require_unsigned_integer "$DIAGNOSTIC_PROCESS_LIMIT" "QUILLUI_RESOURCE_GUARD_DIAGNOSTIC_PROCESS_LIMIT"

if [[ $# -eq 0 ]]; then
  set -- "."
fi

for path in "$@"; do
  check_disk_path "$path"
done

if memory_mib="$(available_memory_mib)"; then
  if (( memory_mib < MIN_AVAILABLE_MEMORY_MIB )); then
    fail_guard "available memory is ${memory_mib}MiB; requires at least ${MIN_AVAILABLE_MEMORY_MIB}MiB"
  fi
  echo "resource guard ok: ${memory_mib}MiB available memory" >&2
else
  echo "resource guard warning: available memory could not be measured" >&2
fi
