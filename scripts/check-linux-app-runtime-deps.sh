#!/usr/bin/env bash
set -euo pipefail

ARTIFACT_DIR="${1:-}"
PRODUCT_NAME="${2:-}"
REPORT_PATH=""

usage() {
  cat <<MSG
Usage: $(basename "$0") ARTIFACT_DIR PRODUCT_NAME [--report PATH]

Audits dynamic runtime dependencies for a packaged Linux app artifact.
Fails when ldd reports unresolved libraries and writes a TSV dependency report.
MSG
}

if (($# >= 2)); then
  shift 2
else
  set --
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --report)
      REPORT_PATH="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [[ -z "$ARTIFACT_DIR" || -z "$PRODUCT_NAME" ]]; then
  usage >&2
  exit 64
fi

if ! command -v ldd >/dev/null 2>&1; then
  echo "ldd is required to audit Linux runtime dependencies." >&2
  exit 69
fi

ARTIFACT_DIR="$(cd "$ARTIFACT_DIR" && pwd)"
BINARY_PATH="$ARTIFACT_DIR/bin/$PRODUCT_NAME"

if [[ ! -x "$BINARY_PATH" ]]; then
  echo "Packaged app binary is missing or not executable: $BINARY_PATH" >&2
  exit 66
fi

if [[ -z "$REPORT_PATH" ]]; then
  REPORT_PATH="$ARTIFACT_DIR/metadata/$PRODUCT_NAME-runtime-deps.tsv"
fi
mkdir -p "$(dirname "$REPORT_PATH")"

LDD_OUTPUT="$(mktemp)"
trap 'rm -f "$LDD_OUTPUT"' EXIT
ldd "$BINARY_PATH" > "$LDD_OUTPUT"

python3 - "$LDD_OUTPUT" "$REPORT_PATH" "$ARTIFACT_DIR" <<'PY'
import os
import re
import sys

ldd_path, report_path, artifact_dir = sys.argv[1:4]
rows = []
unresolved = []

def classify(name, path):
    if path == "not found":
        return "unresolved"
    if not path:
        return "virtual"
    real_path = os.path.realpath(path)
    artifact_real = os.path.realpath(artifact_dir)
    if real_path == artifact_real or real_path.startswith(artifact_real + os.sep):
        return "artifact-bundled"
    if "/swift/linux/" in real_path or name.startswith(("libswift", "libFoundation", "libdispatch", "libBlocksRuntime")):
        return "swift-runtime"
    if os.path.basename(real_path).startswith("ld-linux"):
        return "loader"
    return "system"

for raw_line in open(ldd_path, encoding="utf-8", errors="replace"):
    line = raw_line.strip()
    if not line:
        continue
    if "=>" in line:
        name, rest = [part.strip() for part in line.split("=>", 1)]
        if rest.startswith("not found"):
            path = "not found"
        else:
            path = rest.split(" (", 1)[0].strip()
    else:
        parts = line.split(" (", 1)
        name = os.path.basename(parts[0].strip()) or parts[0].strip()
        path = parts[0].strip() if parts[0].startswith("/") else ""

    kind = classify(name, path)
    if kind == "unresolved":
        unresolved.append(name)
    rows.append((name, kind, path))

with open(report_path, "w", encoding="utf-8") as report:
    report.write("library\tkind\tpath\n")
    for name, kind, path in rows:
        report.write(f"{name}\t{kind}\t{path}\n")

swift_count = sum(1 for _, kind, _ in rows if kind == "swift-runtime")
system_count = sum(1 for _, kind, _ in rows if kind == "system")
bundled_count = sum(1 for _, kind, _ in rows if kind == "artifact-bundled")
print(
    f"runtime deps ok: {len(rows)} libraries "
    f"({swift_count} swift-runtime, {system_count} system, {bundled_count} artifact-bundled)"
)

if unresolved:
    raise SystemExit("Unresolved runtime dependencies: " + ", ".join(unresolved))
PY

printf 'Runtime dependency report written: %s\n' "$REPORT_PATH"
