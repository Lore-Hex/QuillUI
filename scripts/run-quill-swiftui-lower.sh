#!/usr/bin/env bash
set -euo pipefail

if (( $# != 1 )); then
  cat >&2 <<'MSG'
Usage: scripts/run-quill-swiftui-lower.sh GENERATED_SOURCE_DIR

Runs the SwiftUI source-lowering tool from an isolated helper package so
optional upstream app fixtures in the repository do not affect generated app
builds.
MSG
  exit 64
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$1"

if [[ -n "${QUILLUI_SWIFTUI_LOWER:-}" ]]; then
  exec "$QUILLUI_SWIFTUI_LOWER" "$SOURCE_DIR"
fi

TOOL_PACKAGE_DIR="${QUILLUI_SWIFTUI_LOWER_PACKAGE_DIR:-$ROOT_DIR/.build/quill-swiftui-lower-package}"
TOOL_SCRATCH_PATH="${QUILLUI_SWIFTUI_LOWER_SCRATCH_PATH:-$ROOT_DIR/.build/quill-swiftui-lower-tool}"

if [[ -z "$TOOL_PACKAGE_DIR" || "$TOOL_PACKAGE_DIR" == "/" || "$TOOL_PACKAGE_DIR" == "$ROOT_DIR" ]]; then
  echo "Refusing unsafe SwiftUI lower package directory: ${TOOL_PACKAGE_DIR:-<empty>}" >&2
  exit 73
fi

mkdir -p "$TOOL_PACKAGE_DIR/Sources"
rm -rf \
  "$TOOL_PACKAGE_DIR/Sources/QuillSourceLowering" \
  "$TOOL_PACKAGE_DIR/Sources/quill-lower-swiftui"
ln -s "$ROOT_DIR/Sources/QuillSourceLowering" "$TOOL_PACKAGE_DIR/Sources/QuillSourceLowering"
ln -s "$ROOT_DIR/Sources/quill-lower-swiftui" "$TOOL_PACKAGE_DIR/Sources/quill-lower-swiftui"

cat > "$TOOL_PACKAGE_DIR/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuillSwiftUILowerToolPackage",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "quill-lower-swiftui", targets: ["quill-lower-swiftui"])
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
            name: "quill-lower-swiftui",
            dependencies: ["QuillSourceLowering"],
            path: "Sources/quill-lower-swiftui"
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
  quill-lower-swiftui \
  "$SOURCE_DIR"
