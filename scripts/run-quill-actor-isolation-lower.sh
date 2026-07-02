#!/usr/bin/env bash
set -euo pipefail

if (( $# != 1 )); then
  cat >&2 <<'MSG'
Usage: scripts/run-quill-actor-isolation-lower.sh GENERATED_SOURCE_DIR

Runs the opt-in actor-isolation source-lowering tool from an isolated helper
package so optional upstream app fixtures in the repository do not affect
generated app builds. Only headless single-threaded profiles (Enchanted /
Quill Chat) should call this; apps that keep real Swift concurrency must not.
MSG
  exit 64
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$1"

if [[ -n "${QUILLUI_ACTOR_ISOLATION_LOWER:-}" ]]; then
  exec "$QUILLUI_ACTOR_ISOLATION_LOWER" "$SOURCE_DIR"
fi

TOOL_PACKAGE_DIR="${QUILLUI_ACTOR_ISOLATION_LOWER_PACKAGE_DIR:-$ROOT_DIR/.build/quill-actor-isolation-lower-package}"
TOOL_SCRATCH_PATH="${QUILLUI_ACTOR_ISOLATION_LOWER_SCRATCH_PATH:-$ROOT_DIR/.build/quill-actor-isolation-lower-tool}"

if [[ -z "$TOOL_PACKAGE_DIR" || "$TOOL_PACKAGE_DIR" == "/" || "$TOOL_PACKAGE_DIR" == "$ROOT_DIR" ]]; then
  echo "Refusing unsafe actor-isolation lower package directory: ${TOOL_PACKAGE_DIR:-<empty>}" >&2
  exit 73
fi

mkdir -p "$TOOL_PACKAGE_DIR/Sources"
rm -rf \
  "$TOOL_PACKAGE_DIR/Sources/QuillSourceLowering" \
  "$TOOL_PACKAGE_DIR/Sources/quill-lower-actor-isolation"
ln -s "$ROOT_DIR/Sources/QuillSourceLowering" "$TOOL_PACKAGE_DIR/Sources/QuillSourceLowering"
ln -s "$ROOT_DIR/Sources/quill-lower-actor-isolation" "$TOOL_PACKAGE_DIR/Sources/quill-lower-actor-isolation"

cat > "$TOOL_PACKAGE_DIR/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuillActorIsolationLowerToolPackage",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "quill-lower-actor-isolation", targets: ["quill-lower-actor-isolation"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0")
    ],
    targets: [
        .target(
            name: "QuillSourceLowering",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ],
            path: "Sources/QuillSourceLowering"
        ),
        .executableTarget(
            name: "quill-lower-actor-isolation",
            dependencies: ["QuillSourceLowering"],
            path: "Sources/quill-lower-actor-isolation"
        )
    ]
)
SWIFT

swift_run_args=(
  run
  --package-path "$TOOL_PACKAGE_DIR"
  --scratch-path "$TOOL_SCRATCH_PATH"
  --disable-index-store
  --disable-sandbox
)
if [[ "${QUILLUI_SWIFT_JOBS:-}" =~ ^[0-9]+$ && "${QUILLUI_SWIFT_JOBS:-}" -gt 0 ]]; then
  swift_run_args+=(--jobs "$QUILLUI_SWIFT_JOBS")
fi

exec swift "${swift_run_args[@]}" \
  quill-lower-actor-isolation \
  "$SOURCE_DIR"
