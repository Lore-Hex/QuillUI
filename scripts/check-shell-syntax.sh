#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

result=0
while IFS= read -r script; do
  echo "==> bash -n $script"
  if ! bash -n "$script"; then
    result=1
  fi
done < <(find scripts -type f -name '*.sh' | sort)

exit "$result"
