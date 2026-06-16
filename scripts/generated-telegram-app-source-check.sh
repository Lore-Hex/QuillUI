#!/usr/bin/env bash
set -euo pipefail

# Generated Telegram-Mac app-source check.
#
# Mirrors the upstream Telegram-Mac app target (~950 Swift files) into a
# generated SwiftPM package wired against the same mirrored upstream package
# tree the package-island check builds, then compiles it on Linux.
#
# This is a ratchet harness: until the app target is compile-green it runs in
# report mode (QUILLUI_GENERATED_TELEGRAM_APP_MODE=report, the default), which
# never fails the build but prints an error-class histogram so progress is
# measurable. Switch to mode=check to hard-gate once the surface is green.

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "The generated Telegram app-source check requires Linux (QuillObjCCompatibility and the AppKit/Cocoa shim products are Linux-only)." >&2
  exit 64
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/quillui-telegram-source.sh"

UPSTREAM_DIR="$(quillui_resolve_telegram_source_dir "$ROOT_DIR")"
WORK_ROOT="${QUILLUI_GENERATED_TELEGRAM_APP_WORKDIR:-$ROOT_DIR/.build/generated-telegram-app-source-check}"
CACHE_HOME="${QUILLUI_GENERATED_TELEGRAM_APP_HOME:-$ROOT_DIR/.build/generated-telegram-app-source-check-home}"
MODE="${QUILLUI_GENERATED_TELEGRAM_APP_MODE:-report}"

if [[ -z "$WORK_ROOT" || "$WORK_ROOT" == "/" || "$WORK_ROOT" == "$ROOT_DIR" ]]; then
  echo "Refusing unsafe generated work directory: ${WORK_ROOT:-<empty>}" >&2
  exit 73
fi

if [[ ! -d "$UPSTREAM_DIR/Telegram-Mac" ]]; then
  echo "Telegram-Mac sources were not found at: $UPSTREAM_DIR/Telegram-Mac" >&2
  exit 66
fi

rm -rf "$WORK_ROOT"
mkdir -p "$WORK_ROOT" "$CACHE_HOME"

# Reuse the package-island mirror (overlaid-packages + submodule mirrors +
# manifest patching) by running the package check for one tiny package inside
# our work root. The mirror is materialized for every upstream manifest
# regardless of the requested compile set.
QUILLUI_GENERATED_TELEGRAM_PACKAGE_WORKDIR="$WORK_ROOT/mirror" \
QUILLUI_GENERATED_TELEGRAM_PACKAGE_HOME="$CACHE_HOME" \
QUILLUI_TELEGRAM_PACKAGE_CHECK_PACKAGES="ColorPalette" \
  "$ROOT_DIR/scripts/generated-telegram-package-check.sh"

package_mirror_root="$WORK_ROOT/mirror/overlaid-packages"

# The package-island check builds each package in isolation, where the
# mirror's dual exposure (overlaid-packages/<P> and
# submodules/telegram-ios/submodules/<P>, bridged by symlinks) only warns.
# A unified app dependency graph escalates those duplicate identities to
# resolution errors, so canonicalize every path dependency in the mirrored
# manifests to its realpath — one path, one identity.
python3 - "$WORK_ROOT/mirror" <<'PY'
import os
import re
import sys

mirror_root = sys.argv[1]
dep_re = re.compile(r'(\.package\(name:\s*"[^"]+",\s*path:\s*")([^"]+)(")')

for dirpath, dirnames, filenames in os.walk(mirror_root, followlinks=False):
    # SwiftPM scratch/checkout trees are read-only and not ours to rewrite.
    dirnames[:] = [d for d in dirnames if d != '.build']
    if 'Package.swift' not in filenames:
        continue
    manifest_path = os.path.join(dirpath, 'Package.swift')
    text = open(manifest_path).read()

    def canonicalize(match):
        raw = match.group(2)
        resolved = raw if os.path.isabs(raw) else os.path.join(dirpath, raw)
        real = os.path.realpath(resolved)
        return match.group(1) + (real if os.path.isdir(real) else raw) + match.group(3)

    rewritten = dep_re.sub(canonicalize, text)
    if rewritten != text:
        open(manifest_path, 'w').write(rewritten)
PY

app_dir="$WORK_ROOT/app"
app_sources="$app_dir/Sources/TelegramMac"
mkdir -p "$app_sources"

while IFS= read -r swift_source; do
  cp "$swift_source" "$app_sources/"
done < <(find "$UPSTREAM_DIR/Telegram-Mac" -maxdepth 1 -name '*.swift' -print | sort)

python3 "$ROOT_DIR/scripts/lower-telegram-linux-source.py" "$app_dir"
if grep -rqE '#selector|@objc|@IBAction|@IBOutlet|@NSManaged|import os\.log|layerClass' "$app_dir" 2>/dev/null; then
  "$ROOT_DIR/scripts/run-quill-appkit-lower.sh" "$app_dir"
fi
python3 "$ROOT_DIR/scripts/generate-telegram-image-resource-symbols.py" "$app_dir"

# The app entry is lowered away; the check builds a library, not a runnable.
python3 - "$app_sources/AppDelegate.swift" <<'PY'
import sys
path = sys.argv[1]
try:
    text = open(path).read()
except OSError:
    sys.exit(0)
open(path, 'w').write(text.replace('@NSApplicationMain\n', ''))
PY

# Generate the app manifest dynamically: map every module the app sources
# import to whichever mirrored upstream package exports it as a product, or to
# a QuillUI Apple-module product. Unprovided modules are reported as the
# ratchet worklist instead of silently failing one "no such module" at a time.
manifest="$app_dir/Package.swift"
python3 - "$app_sources" "$package_mirror_root" "$ROOT_DIR" "$manifest" <<'PY'
import os
import re
import sys

app_sources, mirror_root, quill_root, manifest_path = sys.argv[1:5]

IMPORT_RE = re.compile(r"^\s*(?:@[A-Za-z_]+\s+)?import\s+(?:class |struct |enum |func |let |var |typealias )?([A-Za-z_][A-Za-z0-9_]*)", re.M)
PRODUCT_RE = re.compile(r'\.library\(\s*name:\s*"([A-Za-z0-9_]+)"')

# Modules the Linux toolchain itself provides (or that are meaningless to wire).
SYSTEM_MODULES = {
    "Foundation", "FoundationNetworking", "FoundationXML", "Dispatch",
    "Glibc", "CoreFoundation", "Swift", "SwiftUI", "Combine", "Testing",
    "XCTest", "ObjectiveC",
}

imports = set()
for name in os.listdir(app_sources):
    if not name.endswith(".swift"):
        continue
    text = open(os.path.join(app_sources, name), encoding="utf-8").read()
    for module in IMPORT_RE.findall(text):
        imports.add(module)

# Index mirrored packages: product name -> package dir basename.
mirror_products = {}
for entry in sorted(os.listdir(mirror_root)):
    package_dir = os.path.join(mirror_root, entry)
    manifest = os.path.join(package_dir, "Package.swift")
    if not os.path.isfile(manifest):
        continue
    for product in PRODUCT_RE.findall(open(manifest, encoding="utf-8").read()):
        mirror_products.setdefault(product, entry)

quill_manifest = open(os.path.join(quill_root, "Package.swift"), encoding="utf-8").read()
quill_products = set(PRODUCT_RE.findall(quill_manifest))
TARGET_RE = re.compile(r'\.target\(\s*name:\s*"([A-Za-z0-9_]+)"')
quill_targets = set(TARGET_RE.findall(quill_manifest))


def mirror_target_names(package):
    manifest = os.path.join(mirror_root, package, "Package.swift")
    try:
        return set(TARGET_RE.findall(open(manifest, encoding="utf-8").read()))
    except OSError:
        return set()

# The lowering and umbrella imports rely on these even when no app file
# imports them directly.
always_quill = ["AppKit", "Cocoa"]

packages = {}
target_products = []
missing = []
for module in sorted(imports):
    if module in SYSTEM_MODULES:
        continue
    if module in mirror_products:
        package = mirror_products[module]
        conflicts = mirror_target_names(package) & quill_targets
        if conflicts:
            # SwiftPM requires globally-unique target names; a mirrored package
            # whose targets collide with the QuillUI root (e.g. upstream Zip vs
            # Sources/ZipShim) cannot join the graph.
            if module in quill_products:
                target_products.append((module, "QuillUI"))
            else:
                missing.append(f"{module} (mirror {package} target-name conflict: {', '.join(sorted(conflicts))})")
            continue
        packages[package] = True
        target_products.append((module, package))
    elif module in quill_products:
        target_products.append((module, "QuillUI"))
    else:
        missing.append(module)

for module in always_quill:
    if module in quill_products and (module, "QuillUI") not in target_products:
        target_products.append((module, "QuillUI"))

lines = []
lines.append("// swift-tools-version:5.9")
lines.append("// Generated by scripts/generated-telegram-app-source-check.sh; do not edit.")
lines.append("import PackageDescription")
lines.append("")
lines.append("let package = Package(")
lines.append('    name: "GeneratedTelegramMacAppSource",')
lines.append("    platforms: [.macOS(.v10_13)],")
lines.append("    products: [")
lines.append('        .library(name: "GeneratedTelegramMacAppSource", targets: ["TelegramMac"]),')
lines.append("    ],")
lines.append("    dependencies: [")
lines.append(f'        .package(name: "QuillUI", path: "{quill_root}"),')
for package in sorted(packages):
    # Realpath: the canonicalization pass rewrites every mirrored manifest to
    # canonical paths, so the app manifest must agree (one path, one identity).
    package_path = os.path.realpath(os.path.join(mirror_root, package))
    lines.append(f'        .package(name: "{package}", path: "{package_path}"),')
lines.append("    ],")
lines.append("    targets: [")
lines.append("        .target(")
lines.append('            name: "TelegramMac",')
lines.append("            dependencies: [")
for module, package in sorted(target_products):
    lines.append(f'                .product(name: "{module}", package: "{package}"),')
lines.append("            ],")
lines.append('            path: "Sources/TelegramMac"')
lines.append("        ),")
lines.append("    ]")
lines.append(")")
open(manifest_path, "w", encoding="utf-8").write("\n".join(lines) + "\n")

print(f"app manifest: {len(target_products)} products from {len(packages)} mirrored packages + QuillUI")
if missing:
    print("app modules with no provider (ratchet worklist):")
    for module in missing:
        print(f"  - {module}")
PY

objc_include_dir="$ROOT_DIR/Sources/QuillObjCCompatibility/include"
log_path="$WORK_ROOT/telegram-mac-app.log"

set +e
HOME="$CACHE_HOME" \
CLANG_MODULE_CACHE_PATH="$WORK_ROOT/module-cache" \
swift build \
  --disable-sandbox \
  --skip-update \
  --jobs "${QUILLUI_GENERATED_TELEGRAM_APP_JOBS:-2}" \
  --package-path "$app_dir" \
  --scratch-path "$WORK_ROOT/.build/app" \
  -Xcc "-I$objc_include_dir" \
  -Xcc "-include" \
  -Xcc "$objc_include_dir/QuillObjCCompatibility/Prelude.h" \
  -Xcc "-fobjc-runtime=gnustep-2.0" \
  -Xcc "-fblocks" \
  -Xcc "-fobjc-arc" \
  >"$log_path" 2>&1
build_status=$?
set -e

error_count="$(grep -c ' error: ' "$log_path" || true)"
printf 'Telegram-Mac app-source build status: %s\n' "$build_status"
printf 'Telegram-Mac app-source error lines: %s\n' "$error_count"
printf 'Top error classes:\n'
grep -oE 'error: [^(]*' "$log_path" | sed 's/[A-Za-z0-9_.]*'"'"'[^'"'"']*'"'"'/<symbol>/g' | sort | uniq -c | sort -rn | head -25 || true
printf 'Log: %s\n' "$log_path"

if [[ "$MODE" == "check" ]]; then
  exit "$build_status"
fi
exit 0
