#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COVERAGE_JSON="${1:-}"

if [[ -z "$COVERAGE_JSON" ]]; then
  COVERAGE_JSON="$(swift test --show-codecov-path 2>/dev/null || true)"
fi

if [[ -z "$COVERAGE_JSON" || ! -f "$COVERAGE_JSON" ]]; then
  cat >&2 <<'MSG'
Coverage JSON was not found.
Run first:

  swift test --enable-code-coverage

or pass an explicit codecov JSON path:

  scripts/coverage-summary.sh .build/.../debug/codecov/QuillUI.json
MSG
  exit 1
fi

python3 - "$COVERAGE_JSON" "$ROOT_DIR" <<'PY'
import json
import sys
from pathlib import Path

coverage_path = Path(sys.argv[1])
root = Path(sys.argv[2])
files = json.loads(coverage_path.read_text())["data"][0]["files"]

def summarize(prefix):
    line_count = line_covered = function_count = function_covered = 0
    region_count = region_covered = 0
    matched = []
    marker = f"/{prefix}/"
    for item in files:
        filename = item["filename"]
        if marker not in filename:
            continue
        summary = item["summary"]
        line_count += summary["lines"]["count"]
        line_covered += summary["lines"]["covered"]
        function_count += summary["functions"]["count"]
        function_covered += summary["functions"]["covered"]
        region_count += summary["regions"]["count"]
        region_covered += summary["regions"]["covered"]
        matched.append((
            filename.split(marker, 1)[1],
            summary["lines"]["covered"],
            summary["lines"]["count"],
            summary["lines"]["percent"],
        ))

    def pct(covered, count):
        return 0.0 if count == 0 else covered / count * 100.0

    print(f"## {prefix}")
    print(f"- Lines: {line_covered}/{line_count} ({pct(line_covered, line_count):.1f}%)")
    print(f"- Functions: {function_covered}/{function_count} ({pct(function_covered, function_count):.1f}%)")
    print(f"- Regions: {region_covered}/{region_count} ({pct(region_covered, region_count):.1f}%)")
    for name, covered, count, percent in sorted(matched):
        print(f"  - {name}: {covered}/{count} ({percent:.1f}%)")

print(f"Coverage JSON: {coverage_path}")
summarize("Sources/QuillUI")
summarize("Sources/QuillKit")
PY
