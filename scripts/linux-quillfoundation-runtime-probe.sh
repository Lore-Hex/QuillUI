#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH_PATH="${QUILLFOUNDATION_RUNTIME_PROBE_SCRATCH:-/tmp/quillfoundation-runtime-probe-build}"
PROBE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/quillfoundation-runtime-probe.XXXXXX")"
PACKAGE_IDENTITY="$(basename "$ROOT_DIR" | tr '[:upper:]' '[:lower:]')"

cleanup() {
  rm -rf "$PROBE_DIR"
}
trap cleanup EXIT

target_triple="$(swift -print-target-info 2>/dev/null | sed -n 's/.*"triple"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 || true)"
case "$target_triple" in
  *linux*) ;;
  *)
    echo "linux-quillfoundation-runtime-probe.sh must run under Swift on Linux; got: ${target_triple:-unknown}" >&2
    exit 69
    ;;
esac

mkdir -p "$PROBE_DIR/Sources/ObjCRuntimeProbe"

cat > "$PROBE_DIR/Package.swift" <<SWIFT
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuillFoundationRuntimeProbe",
    products: [
        .executable(name: "objc-runtime-probe", targets: ["ObjCRuntimeProbe"]),
    ],
    dependencies: [
        .package(path: "$ROOT_DIR"),
    ],
    targets: [
        .executableTarget(
            name: "ObjCRuntimeProbe",
            dependencies: [
                .product(name: "QuillFoundation", package: "$PACKAGE_IDENTITY"),
            ]
        ),
    ]
)
SWIFT

cat > "$PROBE_DIR/Sources/ObjCRuntimeProbe/main.swift" <<'SWIFT'
import Foundation
import QuillFoundation

private final class ObjCRuntimeProbe: NSObject {}

let original = class_getInstanceMethod(ObjCRuntimeProbe.self, Selector("original"))
let replacement = class_getInstanceMethod(ObjCRuntimeProbe.self, Selector("replacement"))

precondition(original != nil, "class_getInstanceMethod returned nil for original selector")
precondition(replacement != nil, "class_getInstanceMethod returned nil for replacement selector")

method_exchangeImplementations(original!, replacement!)
print("objc-runtime-probe ok")
SWIFT

QUILLUI_DISABLE_UPSTREAM_APP_GRAPHS="${QUILLUI_DISABLE_UPSTREAM_APP_GRAPHS:-1}" \
  swift run \
    --package-path "$PROBE_DIR" \
    --disable-index-store \
    --scratch-path "$SCRATCH_PATH" \
    objc-runtime-probe
