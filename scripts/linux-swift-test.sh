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
  target_triple="$(swift -print-target-info 2>/dev/null | sed -n 's/.*"triple"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 || true)"
  for triple in "$target_triple" x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu; do
    [[ -n "$triple" ]] || continue
    mkdir -p "$SCRATCH_PATH/$triple/debug/index/store/v5/units"
  done

  # The Linux suite has historically hung AFTER every test already reported
  # pass/fail: a subprocess spawned by a test (e.g. a GTK/Xvfb child) inherits
  # the `swift test` stdout and never exits, so a plain `swift test | tee` never
  # sees EOF and the step runs until the GitHub job cap (observed 2h+). Run it
  # in its own session, mirror the log with `tail --pid` (no pipe a stray child
  # can wedge), bound it with a hard cap, and kill the whole process group when
  # the test process exits or the cap fires. The literal invocation below keeps
  # the `swift test --scratch-path "$SCRATCH_PATH"` form the contract tests pin.
  swift_test_log="$SCRATCH_PATH/swift-test.log"
  cap_secs="${QUILLUI_SWIFT_TEST_TIMEOUT_SECS:-7200}"   # 120 min; a real run is <55 min, the hang is 3h+
  : > "$swift_test_log"
  set +e
  setsid "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" \
    swift test --scratch-path "$SCRATCH_PATH" ${SWIFT_TEST_ARGS[@]+"${SWIFT_TEST_ARGS[@]}"} \
    > "$swift_test_log" 2>&1 &
  swift_test_pid=$!
  swift_test_pgid="$(ps -o pgid= "$swift_test_pid" 2>/dev/null | tr -d ' ')"
  swift_test_pgid="${swift_test_pgid:-$swift_test_pid}"
  tail -n +1 --pid="$swift_test_pid" -f "$swift_test_log" &
  tail_pid=$!

  timed_out=0
  waited=0
  while kill -0 "$swift_test_pid" 2>/dev/null; do
    if (( waited >= cap_secs )); then
      timed_out=1
      echo ""
      echo "=== swift test exceeded ${cap_secs}s hard cap; killing process group $swift_test_pgid ==="
      kill -KILL "-$swift_test_pgid" 2>/dev/null
      kill -KILL "$swift_test_pid" 2>/dev/null
      break
    fi
    sleep 5
    waited=$((waited + 5))
  done
  wait "$swift_test_pid" 2>/dev/null
  status=$?
  # Reap any strays (the hung GTK/Xvfb child) so this step can exit promptly.
  kill -KILL "-$swift_test_pgid" 2>/dev/null || true
  kill "$tail_pid" 2>/dev/null || true
  wait "$tail_pid" 2>/dev/null || true
  set -e

  if [[ $timed_out -eq 1 ]]; then
    # Salvage: if the runner already printed a clean pass summary before the
    # cap fired, the hang is post-suite teardown, not the tests themselves.
    if grep -qE 'Test run with [0-9]+ test(s)? in [0-9]+ suite(s)? passed' "$swift_test_log" \
       && ! grep -qE 'Test run with .* failed|recorded an issue|(^|[[:space:]/])Tests/.*\.swift:[0-9]+: error:' "$swift_test_log"; then
      echo "=== swift test reported a clean pass before the post-suite hang; treating as success. ==="
      status=0
    else
      echo "=== swift test hit the ${cap_secs}s cap without a clean pass summary; treating as failure. ==="
      status=124
    fi
  fi

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
