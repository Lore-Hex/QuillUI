#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH_PATH=".build-linux"
SWIFT_TEST_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scratch-path)
      if [[ $# -lt 2 ]]; then
        echo "--scratch-path requires a value" >&2
        exit 64
      fi
      SCRATCH_PATH="$2"
      shift 2
      ;;
    --scratch-path=*)
      SCRATCH_PATH="${1#--scratch-path=}"
      shift
      ;;
    *)
      SWIFT_TEST_ARGS+=("$1")
      shift
      ;;
  esac
done

"$ROOT_DIR/scripts/quillui-resource-guard.sh" "$ROOT_DIR" "${TMPDIR:-/tmp}"

"$ROOT_DIR/scripts/prepare-linux-build-backend.sh" --scratch-path "$SCRATCH_PATH"

(
  cd "$ROOT_DIR"
  set +e
  "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" \
    swift test --scratch-path "$SCRATCH_PATH" "${SWIFT_TEST_ARGS[@]}" \
    2>&1 | tee "$SCRATCH_PATH/swift-test.log"
  status=${PIPESTATUS[0]}
  set -e

  if [[ $status -ne 0 ]]; then
    echo ""
    echo "=== XCTest failures (re-extracted; ignore the 'all tests passed' Swift Testing summary above) ==="
    # Extract XCTest errors. They usually look like:
    # Tests/Path/To/File.swift:123: error: -[Suite.Test testName] : XCTAssertEqual failed...
    # We match both relative paths and absolute paths that contain /Tests/
    grep -E '(^|[[:space:]/])Tests/.*\.swift:[0-9]+: error:' "$SCRATCH_PATH/swift-test.log" | head -50 \
      | while IFS= read -r line; do
          # Clean up the line for GitHub annotations if it has absolute paths
          # but for now we just print it as is with the ::error:: prefix.
          echo "::error::$line"
        done
    echo "=== Test run failed with exit code $status ==="
    exit $status
  fi
)
