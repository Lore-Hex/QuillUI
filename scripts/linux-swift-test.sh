#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH_PATH=".build-linux"
SWIFT_TEST_ARGS=()

# Run view-constructing tests on the Linux Swift 6.2 runtime without the strict
# main-actor executor assertion hard-crashing the whole test process.
#
# SwiftUI's View/ViewBuilder are `@MainActor @preconcurrency` (Apple's exact
# shape). Many compatibility/unit tests build views or read `.children`/`.body`
# synchronously, and Swift Testing runs suites on the global concurrent executor.
# Under Swift 6.2 on Linux, invoking that @MainActor content off the main actor
# trips `swift_task_isCurrentExecutorWithFlags` -> `_dispatch_assert_queue_fail`
# (SIGILL, signal 4) — aborting the entire run, not just the one test. macOS CI
# runs the same `swift test` green because Apple's runtime resolves the same
# call without the libdispatch hard-assert. `legacy` is Apple's own migration
# override: `isCurrentExecutor` returns the lenient result instead of trapping,
# making Linux behave like macOS for these synchronous off-actor view builds.
# This is a process-wide safety net so the fix scales to every view-building
# suite (current and future) rather than annotating each one @MainActor.
export SWIFT_IS_CURRENT_EXECUTOR_LEGACY_MODE_OVERRIDE="${SWIFT_IS_CURRENT_EXECUTOR_LEGACY_MODE_OVERRIDE:-legacy}"

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
  target_triple="$(swift -print-target-info 2>/dev/null | sed -n 's/.*"triple"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 || true)"
  for triple in "$target_triple" x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu; do
    [[ -n "$triple" ]] || continue
    mkdir -p "$SCRATCH_PATH/$triple/debug/index/store/v5/units"
  done

  set +e
  "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" \
    swift test --scratch-path "$SCRATCH_PATH" ${SWIFT_TEST_ARGS[@]+"${SWIFT_TEST_ARGS[@]}"} \
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
