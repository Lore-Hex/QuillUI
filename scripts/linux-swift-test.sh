#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH_PATH=".build-linux"
SWIFT_TEST_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --nnw-upstream)
      export QUILLUI_NNW_UPSTREAM=1
      shift
      ;;
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

if [[ "${QUILLUI_NNW_UPSTREAM:-0}" != "1" ]]; then
  for ((i = 0; i < ${#SWIFT_TEST_ARGS[@]}; i++)); do
    filter=""
    case "${SWIFT_TEST_ARGS[$i]}" in
      --filter)
        if ((i + 1 < ${#SWIFT_TEST_ARGS[@]})); then
          filter="${SWIFT_TEST_ARGS[$((i + 1))]}"
        fi
        ;;
      --filter=*)
        filter="${SWIFT_TEST_ARGS[$i]#--filter=}"
        ;;
      *)
        continue
        ;;
    esac

    if [[ "$filter" == *NetNewsWireMacCoreTests* || "$filter" == *NetNewsWireSharedCoreTests* ]]; then
      cat >&2 <<'EOF'
NetNewsWire upstream tests are outside the default Linux package graph.
Pass --nnw-upstream or set QUILLUI_NNW_UPSTREAM=1 so the filtered run cannot pass with zero tests.
EOF
      exit 64
    fi
  done
fi

"$ROOT_DIR/scripts/quillui-resource-guard.sh" "$ROOT_DIR" "${TMPDIR:-/tmp}"

"$ROOT_DIR/scripts/prepare-linux-build-backend.sh" --scratch-path "$SCRATCH_PATH"

(
  cd "$ROOT_DIR"
  target_triple="$(swift -print-target-info 2>/dev/null | sed -n 's/.*"triple"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 || true)"
  for triple in "$target_triple" x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu; do
    [[ -n "$triple" ]] || continue
    mkdir -p "$SCRATCH_PATH/$triple/debug/index/store/v5/units"
  done

  # Build the test bundle FIRST, untimed (a cold all-upstreams build can take
  # the better part of an hour on a CI runner). Then run the suite with a TIGHT
  # timeout: separating the two means the timeout bounds only the (fast) test
  # *run*, not the (slow) build.
  # `--filter` is a `swift test`-only option; `swift build --build-tests`
  # rejects it ("Unknown option '--filter'", exit 64). Strip it (and its value)
  # for the build phase — building the whole test bundle is fine; the filter
  # still applies to the test run below.
  BUILD_ARGS=()
  skip_next=0
  for a in ${SWIFT_TEST_ARGS[@]+"${SWIFT_TEST_ARGS[@]}"}; do
    if [[ $skip_next -eq 1 ]]; then skip_next=0; continue; fi
    case "$a" in
      --filter) skip_next=1; continue ;;
      --filter=*) continue ;;
      *) BUILD_ARGS+=("$a") ;;
    esac
  done

  EXTRA_BUILD_ARGS=()
  EXTRA_TEST_ARGS=()

  # The full Linux package test bundle is large enough that the default BFD
  # linker can OOM or emit unsupported relocation errors late in the build,
  # after the useful compile work has already succeeded. Prefer lld whenever it
  # is available; callers can set QUILLUI_SWIFT_TEST_USE_LLD=0 to opt out.
  use_lld="${QUILLUI_SWIFT_TEST_USE_LLD:-1}"
  has_linker_choice=0
  for a in ${SWIFT_TEST_ARGS[@]+"${SWIFT_TEST_ARGS[@]}"}; do
    case "$a" in
      -use-ld=*|--use-ld=*|*use-ld=*) has_linker_choice=1 ;;
    esac
  done
  if [[ "$use_lld" != "0" && "$use_lld" != "off" && $has_linker_choice -eq 0 ]]; then
    if command -v ld.lld >/dev/null 2>&1; then
      EXTRA_BUILD_ARGS+=("-Xswiftc" "-use-ld=lld")
      EXTRA_TEST_ARGS+=("-Xswiftc" "-use-ld=lld")
      echo "=== Using ld.lld for Linux Swift test links ==="
    elif [[ "$use_lld" == "required" ]]; then
      echo "QUILLUI_SWIFT_TEST_USE_LLD=required but ld.lld was not found" >&2
      exit 69
    fi
  fi

  # Index-store writes are not needed for CI/test execution and have caused
  # corrupted JSON noise under memory pressure. Keep it disabled unless the
  # caller explicitly passed an index-store option or opted out via env.
  disable_index_store="${QUILLUI_SWIFT_TEST_DISABLE_INDEX_STORE:-1}"
  has_index_store_choice=0
  for a in ${SWIFT_TEST_ARGS[@]+"${SWIFT_TEST_ARGS[@]}"}; do
    case "$a" in
      --auto-index-store|--enable-index-store|--disable-index-store) has_index_store_choice=1 ;;
    esac
  done
  if [[ "$disable_index_store" != "0" && "$disable_index_store" != "off" && $has_index_store_choice -eq 0 ]]; then
    EXTRA_BUILD_ARGS+=("--disable-index-store")
    EXTRA_TEST_ARGS+=("--disable-index-store")
  fi

  set +e
  "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" \
    swift build --build-tests --scratch-path "$SCRATCH_PATH" ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"} ${EXTRA_BUILD_ARGS[@]+"${EXTRA_BUILD_ARGS[@]}"} \
    2>&1 | tee "$SCRATCH_PATH/swift-test-build.log"
  build_status=${PIPESTATUS[0]}
  if [[ $build_status -ne 0 ]]; then
    set -e
    echo "=== Test build failed with exit code $build_status ==="
    exit $build_status
  fi

  # swift-corelibs-foundation does not synthesize an app bundle for Linux
  # test executables. If the repo has app-style Info.plist metadata, place it
  # beside the built executable directory so Bundle.main.object(forInfoDictionaryKey:)
  # behaves like AppKit code expects during compatibility tests.
  if [[ -f "$ROOT_DIR/Info.plist" ]]; then
    bin_path="$(swift build --scratch-path "$SCRATCH_PATH" --show-bin-path ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"} ${EXTRA_BUILD_ARGS[@]+"${EXTRA_BUILD_ARGS[@]}"} 2>/dev/null || true)"
    if [[ -n "$bin_path" && -d "$bin_path" ]]; then
      cp "$ROOT_DIR/Info.plist" "$bin_path/Info.plist"
    fi
  fi

  # Pre-build the isolated SwiftSyntax source-lowering tool ONCE, untimed, and
  # pin QUILLUI_SOURCE_LOWER to the resulting binary. The QuillData lowering
  # test otherwise cold-builds swift-syntax in a throwaway scratch INSIDE the
  # timeout-bounded test run; on a constrained CI runner that took >900s and
  # wedged the whole suite (it completes in ~49s on 2 local cores). Execing a
  # prebuilt binary makes that test a fast no-op. run-quill-source-lower.sh
  # short-circuits to $QUILLUI_SOURCE_LOWER before any build when it is set, so
  # the test reuses this binary without touching its own scratch override.
  # Skipped for --filter runs (e.g. the offscreen ImageRenderer smoke), which
  # don't exercise the lowering test.
  warm_lower=1
  for arg in ${SWIFT_TEST_ARGS[@]+"${SWIFT_TEST_ARGS[@]}"}; do
    case "$arg" in --filter|--filter=*) warm_lower=0 ;; esac
  done
  if [[ $warm_lower -eq 1 ]]; then
    lower_pkg="$ROOT_DIR/.build/quill-source-lower-package"
    lower_scratch="$ROOT_DIR/.build/quill-source-lower-tool"
    warm_dir="$(mktemp -d)"
    printf 'import Foundation\n' > "$warm_dir/Warm.swift"
    # NOTE: leave "$warm_dir/out" uncreated — quill-source-lower refuses to run
    # into an existing output directory (it guards against clobbering sources).
    if QUILLUI_SOURCE_LOWER_PACKAGE_DIR="$lower_pkg" \
       QUILLUI_SOURCE_LOWER_SCRATCH_PATH="$lower_scratch" \
       "$ROOT_DIR/scripts/run-quill-source-lower.sh" "$warm_dir" "$warm_dir/out" \
       > "$SCRATCH_PATH/quill-source-lower-warmup.log" 2>&1; then
      lower_bin_dir="$(swift build --package-path "$lower_pkg" --scratch-path "$lower_scratch" --show-bin-path 2>/dev/null || true)"
      if [[ -n "$lower_bin_dir" && -x "$lower_bin_dir/quill-source-lower" ]]; then
        export QUILLUI_SOURCE_LOWER="$lower_bin_dir/quill-source-lower"
        echo "=== Pinned QUILLUI_SOURCE_LOWER=$QUILLUI_SOURCE_LOWER (prebuilt; lowering test skips the cold swift-syntax build) ==="
      fi
    else
      echo "=== source-lower tool warmup failed; the lowering test will build it itself (see $SCRATCH_PATH/quill-source-lower-warmup.log) ==="
    fi
    rm -rf "$warm_dir"
  fi

  # `timeout`: the suite has been observed to finish reporting and then HANG —
  # a leaked subprocess (GTK/Xvfb) keeps the swift-test process alive, so the
  # step burns the whole job budget for nothing (a ~2h hang was seen, while the
  # run itself completes in seconds and does not reproduce locally). Cap the
  # run; judge the result by the suite's own reported summary in the log, NOT
  # the killed-process exit code. (TEST_RUN_TIMEOUT overridable.)
  : "${TEST_RUN_TIMEOUT:=900}"
  # `stdbuf -oL -eL`: GitHub's non-TTY stdout makes swift-testing BLOCK-buffer
  # its output. When the process is SIGKILLed on a post-suite leak, the final
  # "Test run with N tests … passed" summary is still stuck in that buffer and
  # lost, so the rescue below can't find it and a clean run is misreported as a
  # hang (the buffered tail only shows some test's "started" line). Line-buffer
  # so every result — and the completion summary — reaches the log immediately.
  # (LD_PRELOAD set by stdbuf is inherited by the swift grandchild.)
  timeout --signal=KILL "$TEST_RUN_TIMEOUT" \
    stdbuf -oL -eL \
    "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" \
    swift test --skip-build --scratch-path "$SCRATCH_PATH" ${SWIFT_TEST_ARGS[@]+"${SWIFT_TEST_ARGS[@]}"} ${EXTRA_TEST_ARGS[@]+"${EXTRA_TEST_ARGS[@]}"} \
    2>&1 | tee "$SCRATCH_PATH/swift-test.log"
  status=${PIPESTATUS[0]}
  set -e

  # A killed-by-timeout run (124, or 137 for SIGKILL) is only a real failure if
  # the suite never finished or reported failures. If the log shows a completed
  # run with no failures, the kill was a post-suite hang — treat it as a pass.
  if [[ $status -eq 124 || $status -eq 137 ]]; then
    if grep -qE 'Test run with [0-9]+ tests? in [0-9]+ suites? (passed|failed)' "$SCRATCH_PATH/swift-test.log"; then
      if grep -qE 'Test run with .* failed|(^|[[:space:]/])Tests/.*\.swift:[0-9]+: error:' "$SCRATCH_PATH/swift-test.log"; then
        echo "=== Suite reported FAILURES (then the process hung and was killed) ==="
        status=1
      else
        echo "=== Suite reported PASS; the process hung post-suite (leaked subprocess) and was killed — treating as success ==="
        status=0
      fi
    else
      echo "=== HANG: the suite never reported completion within ${TEST_RUN_TIMEOUT}s ==="
      echo "--- last 5 tests that completed before the hang ---"
      grep -E '(✔|✘) Test ' "$SCRATCH_PATH/swift-test.log" | tail -5
      echo "--- tests started but never completed (with line-buffered output, the hang is among these) ---"
      comm -23 \
        <(grep -oE '◇ Test "[^"]+" started' "$SCRATCH_PATH/swift-test.log" | sed -E 's/◇ Test "(.*)" started/\1/' | sort -u) \
        <(grep -oE '(✔|✘) Test "[^"]+"' "$SCRATCH_PATH/swift-test.log" | sed -E 's/[^"]*"(.*)"/\1/' | sort -u) \
        | head -20
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
