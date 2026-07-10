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

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE_DIR="$1"
OUTPUT_DIR="$2"

if [[ -n "${QUILLUI_SOURCE_LOWER:-}" ]]; then
  exec "$QUILLUI_SOURCE_LOWER" "$SOURCE_DIR" "$OUTPUT_DIR"
fi

TOOL_CACHE_KEY="$(printf '%s' "$ROOT_DIR" | cksum | awk '{print $1}')"
TOOL_PACKAGE_DIR="${QUILLUI_SOURCE_LOWER_PACKAGE_DIR:-$ROOT_DIR/.build/quill-source-lower-package-$TOOL_CACHE_KEY}"
TOOL_SCRATCH_PATH="${QUILLUI_SOURCE_LOWER_SCRATCH_PATH:-$ROOT_DIR/.build/quill-source-lower-tool-$TOOL_CACHE_KEY}"

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

if [[ -f "$ROOT_DIR/third_party/swift-syntax/Package.swift" ]]; then
  SWIFT_SYNTAX_DEPENDENCY="        .package(name: \"swift-syntax\", path: \"$ROOT_DIR/third_party/swift-syntax\")"
else
  SWIFT_SYNTAX_DEPENDENCY="        .package(url: \"https://github.com/swiftlang/swift-syntax.git\", from: \"600.0.0\")"
fi

cat > "$TOOL_PACKAGE_DIR/Package.swift" <<SWIFT
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuillSourceLowerToolPackage",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "quill-source-lower", targets: ["quill-source-lower"])
    ],
    dependencies: [
${SWIFT_SYNTAX_DEPENDENCY}
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
  quill-source-lower \
  "$SOURCE_DIR" \
  "$OUTPUT_DIR"
