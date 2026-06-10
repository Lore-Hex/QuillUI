#!/usr/bin/env python3
import re
import sys
from pathlib import Path


IMPORT_TO_PRODUCT = {
    "AppKit": "AppKit",
    "AVFoundation": "AVFoundation",
    "Accelerate": "Accelerate",
    "AudioToolbox": "AudioToolbox",
    "Cocoa": "Cocoa",
    "Compression": "Compression",
    "CoreGraphics": "CoreGraphics",
    "CoreImage": "CoreImage",
    "CoreLocation": "CoreLocation",
    "CoreMedia": "CoreMedia",
    "CoreSpotlight": "CoreSpotlight",
    "CoreText": "CoreText",
    "CoreVideo": "CoreVideo",
    "COSUnfairLock": "COSUnfairLock",
    "NaturalLanguage": "NaturalLanguage",
    "ImageIO": "ImageIO",
    "IOKit": "IOKit",
    "IOSurface": "IOSurface",
    "JavaScriptCore": "JavaScriptCore",
    "LinkPresentation": "LinkPresentation",
    "Metal": "Metal",
    "MetalKit": "MetalKit",
    "MetalPerformanceShaders": "MetalPerformanceShaders",
    "MediaPlayer": "MediaPlayer",
    "Network": "Network",
    "QuillFoundation": "QuillFoundation",
    "QuartzCore": "QuartzCore",
    "StoreKit": "StoreKit",
    "VideoToolbox": "VideoToolbox",
    "Vision": "Vision",
    "WebKit": "WebKit",
}


def imported_products(package_dir: Path) -> list[str]:
    products: set[str] = set()
    sources_dir = package_dir / "Sources"
    search_roots = [sources_dir, package_dir] if sources_dir.exists() else [package_dir]
    seen_files: set[Path] = set()

    for search_root in search_roots:
        for swift_file in sorted(search_root.rglob("*.swift")):
            try:
                relative_parts = swift_file.relative_to(package_dir).parts
            except ValueError:
                relative_parts = swift_file.parts
            if any(part in {".build", ".git", ".swiftpm"} for part in relative_parts):
                continue
            resolved = swift_file.resolve()
            if resolved in seen_files:
                continue
            seen_files.add(resolved)
            try:
                text = swift_file.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                text = swift_file.read_text(encoding="utf-8", errors="ignore")
            for module, product in IMPORT_TO_PRODUCT.items():
                if re.search(rf"^\s*import\s+{re.escape(module)}\b", text, flags=re.MULTILINE):
                    products.add(product)
    return sorted(products)


def insert_quill_dependency(manifest: str, quill_root: str) -> str:
    if '.package(name: "QuillUI"' in manifest:
        return manifest
    pattern = re.compile(r"^(\s*)dependencies:\s*\[\s*$", re.MULTILINE)

    def replace(match: re.Match[str]) -> str:
        indent = match.group(1)
        if len(indent) != 4:
            return match.group(0)
        return f'{match.group(0)}\n{indent}    .package(name: "QuillUI", path: "{quill_root}"),'

    lowered, count = pattern.subn(replace, manifest, count=1)
    if count == 0:
        raise SystemExit("could not find package-level dependencies array")
    return lowered


def insert_target_products(manifest: str, products: list[str]) -> str:
    if not products:
        return manifest

    product_lines = [
        f'.product(name: "{product}", package: "QuillUI", condition: nil)'
        for product in products
    ]
    lines = manifest.splitlines()
    output: list[str] = []

    for line in lines:
        stripped = line.lstrip()
        indent = line[: len(line) - len(stripped)]
        is_target_dependency = len(indent) >= 12 and stripped.startswith("dependencies: [")

        if not is_target_dependency:
            output.append(line)
            continue

        if all(product_line in line for product_line in product_lines):
            output.append(line)
            continue

        prefix, suffix = line.split("[", 1)
        inner, separator, trailing = suffix.partition("]")
        output.append(prefix + "[")
        for product_line in product_lines:
            output.append(f"{indent}    {product_line},")
        if separator:
            inner = inner.strip()
            if inner:
                output.append(f"{indent}    {inner}")
            output.append(f"{indent}]{trailing}")
        else:
            inner = inner.strip()
            if inner:
                output.append(f"{indent}    {inner}")

    return "\n".join(output) + ("\n" if manifest.endswith("\n") else "")


PRODUCT_ATTRIBUTION_RE = re.compile(
    r'\.product\(name:\s*"([A-Za-z0-9_]+)",\s*package:\s*"([A-Za-z0-9_]+)"'
)
PACKAGE_DECLARATION_RE = re.compile(r'\.package\(name:\s*"([A-Za-z0-9_]+)"')


def fix_product_package_attribution(manifest: str) -> str:
    """Repair upstream product->package mis-attributions.

    Upstream manifests occasionally attribute a product to a sibling package
    that merely re-exports it (e.g. InAppPurchaseManager declares
    `.product(name: "TGUIKit", package: "Postbox")`). Isolated package-island
    builds tolerate that; a unified dependency graph rejects it. When the
    product name matches a package the manifest itself declares, attribute the
    product to that package.
    """
    declared = set(PACKAGE_DECLARATION_RE.findall(manifest))

    def repair(match: "re.Match[str]") -> str:
        product, package = match.group(1), match.group(2)
        if product != package and product in declared:
            return f'.product(name: "{product}", package: "{product}"'
        return match.group(0)

    return PRODUCT_ATTRIBUTION_RE.sub(repair, manifest)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: patch-telegram-package-manifest.py PACKAGE_DIR QUILLUI_ROOT")

    package_dir = Path(sys.argv[1])
    quill_root = sys.argv[2]
    manifest_path = package_dir / "Package.swift"

    manifest = manifest_path.read_text(encoding="utf-8")
    repaired = fix_product_package_attribution(manifest)

    products = imported_products(package_dir)
    if not products:
        if repaired != manifest:
            manifest_path.write_text(repaired, encoding="utf-8")
        return

    manifest = insert_quill_dependency(repaired, quill_root)
    manifest = insert_target_products(manifest, products)
    manifest_path.write_text(manifest, encoding="utf-8")


if __name__ == "__main__":
    main()
