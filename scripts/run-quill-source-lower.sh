#!/usr/bin/env bash
set -euo pipefail

if (( $# != 2 )); then
  cat >&2 <<'MSG'
Usage: scripts/run-quill-source-lower.sh SOURCE_DIR OUTPUT_DIR

Runs the SwiftSyntax source-lowering tool from an isolated helper package so
optional upstream app fixtures in the repository do not affect generated app
builds.
MSG
  exit 64
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$1"
OUTPUT_DIR="$2"

if [[ -n "${QUILLUI_SOURCE_LOWER:-}" ]]; then
  exec "$QUILLUI_SOURCE_LOWER" "$SOURCE_DIR" "$OUTPUT_DIR"
fi

TOOL_PACKAGE_DIR="${QUILLUI_SOURCE_LOWER_PACKAGE_DIR:-$ROOT_DIR/.build/quill-source-lower-package}"
TOOL_SCRATCH_PATH="${QUILLUI_SOURCE_LOWER_SCRATCH_PATH:-$ROOT_DIR/.build/quill-source-lower-tool}"

if [[ -z "$TOOL_PACKAGE_DIR" || "$TOOL_PACKAGE_DIR" == "/" || "$TOOL_PACKAGE_DIR" == "$ROOT_DIR" ]]; then
  echo "Refusing unsafe source-lower package directory: ${TOOL_PACKAGE_DIR:-<empty>}" >&2
  exit 73
fi

mkdir -p "$TOOL_PACKAGE_DIR/Sources"
rm -rf \
  "$TOOL_PACKAGE_DIR/Sources/QuillSourceLowering" \
  "$TOOL_PACKAGE_DIR/Sources/quill-source-lower"
ln -s "$ROOT_DIR/Sources/QuillSourceLowering" "$TOOL_PACKAGE_DIR/Sources/QuillSourceLowering"
ln -s "$ROOT_DIR/Sources/quill-source-lower" "$TOOL_PACKAGE_DIR/Sources/quill-source-lower"

cat > "$TOOL_PACKAGE_DIR/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuillSourceLowerToolPackage",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "quill-source-lower", targets: ["quill-source-lower"])
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
            name: "quill-source-lower",
            dependencies: ["QuillSourceLowering"],
            path: "Sources/quill-source-lower"
        )
    ]
)
SWIFT

exec swift run \
  --package-path "$TOOL_PACKAGE_DIR" \
  --scratch-path "$TOOL_SCRATCH_PATH" \
  --disable-sandbox \
  quill-source-lower \
  "$SOURCE_DIR" \
  "$OUTPUT_DIR"
