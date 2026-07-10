#!/usr/bin/env python3
"""Discover local SwiftPM package products imported by a generated app source tree."""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path


IMPORT_RE = re.compile(
    r"^\s*(?:(?:@testable|@_exported|@_implementationOnly)\s+)*import\s+([A-Za-z_][A-Za-z0-9_]*)\b",
    re.MULTILINE,
)
PACKAGE_NAME_RE = re.compile(r"Package\s*\(\s*name:\s*\"([^\"]+)\"", re.DOTALL)
PRODUCT_RE = re.compile(
    r"\.(?:library|executable|plugin|macro)\s*\(\s*name:\s*\"([^\"]+)\"",
    re.DOTALL,
)
EXPORTED_CUSTOM_TARGET_RE = re.compile(
    r"\.target\(\s*kind:\s*\.exported\s*,\s*name:\s*\"([^\"]+)\"",
    re.DOTALL,
)
QUILL_PROVIDED_IMPORTS = {
    "ActivityIndicatorView",
    "Alamofire",
    "AppKit",
    "ApplicationServices",
    "AsyncAlgorithms",
    "AVFoundation",
    "AVKit",
    "Carbon",
    "Cocoa",
    "Combine",
    "CoreGraphics",
    "CoreImage",
    "CoreSpotlight",
    "CoreText",
    "CoreTransferable",
    "CryptoKit",
    "IOKit",
    "KeyboardShortcuts",
    "Magnet",
    "MarkdownUI",
    "Network",
    "OllamaKit",
    "OSLog",
    "PDFKit",
    "PhotosUI",
    "QuickLook",
    "QuickLookUI",
    "QuillData",
    "QuillFoundation",
    "QuillKit",
    "QuillShims",
    "QuillUI",
    "Security",
    "ServiceManagement",
    "Sparkle",
    "Splash",
    "SwiftData",
    "SwiftUI",
    "SwiftUIIntrospect",
    "UIKit",
    "UniformTypeIdentifiers",
    "UserNotifications",
    "Vortex",
    "WebKit",
    "WrappingHStack",
}


@dataclass(frozen=True)
class LocalProduct:
    product_name: str
    package_name: str
    package_path: Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Scan Swift imports and local Package.swift manifests, then emit package "
            "dependency lines plus matching generated target dependency tokens."
        )
    )
    parser.add_argument("--root-dir", required=True, type=Path)
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--package-dependencies-out", required=True, type=Path)
    parser.add_argument("--target-dependencies-out", required=True, type=Path)
    parser.add_argument(
        "--exclude-package-root",
        action="append",
        default=[],
        type=Path,
        help=(
            "Local Package.swift root to ignore. Use this when the app package "
            "targets are copied into the generated package and should not also "
            "be added back as product dependencies."
        ),
    )
    return parser.parse_args()


def swift_imports(source_dir: Path) -> set[str]:
    imports: set[str] = set()
    for source_file in source_dir.rglob("*.swift"):
        try:
            source = source_file.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            source = source_file.read_text(encoding="utf-8", errors="ignore")
        imports.update(IMPORT_RE.findall(source))
    return imports


def local_package_manifests(root_dir: Path, excluded_package_roots: set[Path]) -> list[Path]:
    manifests: list[Path] = []
    for relative_root in ("third_party", ".upstream", "vendor/apps"):
        base = root_dir / relative_root
        if not base.is_dir():
            continue
        for manifest in sorted(base.rglob("Package.swift")):
            if manifest.parent.resolve() in excluded_package_roots:
                continue
            manifests.append(manifest)
    return manifests


def parse_manifest(manifest: Path) -> list[LocalProduct]:
    text = manifest.read_text(encoding="utf-8", errors="ignore")
    package_match = PACKAGE_NAME_RE.search(text)
    if package_match is None:
        return []

    package_path = manifest.parent.resolve()
    manifest_package_name = package_match.group(1)
    # SwiftPM package identity follows the dependency location/name used in the
    # root manifest. Some packages intentionally use a different manifest name
    # from their URL identity, e.g. `GRDB.swift` has `Package(name: "GRDB")`.
    # Preserve the vendored directory identity so generated app packages match
    # QuillUI's root dependency and do not resolve duplicate packages.
    if package_path.name != manifest_package_name and ("." in package_path.name or "-" in package_path.name):
        package_name = package_path.name
    else:
        package_name = manifest_package_name
    products: list[LocalProduct] = []
    product_names = set(PRODUCT_RE.findall(text))

    # Some packages, notably swift-collections, build their product list from
    # local manifest data instead of spelling every `.library` call literally.
    # Treat exported custom targets as products so imports such as
    # `OrderedCollections` and `DequeModule` map back to the local package.
    product_names.update(EXPORTED_CUSTOM_TARGET_RE.findall(text))

    for product_name in sorted(product_names):
        products.append(
            LocalProduct(
                product_name=product_name,
                package_name=package_name,
                package_path=package_path,
            )
        )
    return products


def package_dependency_line(product: LocalProduct) -> str:
    quoted_path = json.dumps(str(product.package_path))
    return f'.package(name: "{product.package_name}", path: {quoted_path})'


def target_dependency_token(product: LocalProduct) -> str:
    return f"product:{product.product_name}:{product.package_name}"


def write_lines(path: Path, lines: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(f"{line}\n" for line in lines), encoding="utf-8")


def main() -> int:
    args = parse_args()
    root_dir = args.root_dir.resolve()
    source_dir = args.source_dir.resolve()
    excluded_package_roots = {path.resolve() for path in args.exclude_package_root}

    imports = swift_imports(source_dir)
    by_product: dict[str, LocalProduct] = {}
    for manifest in local_package_manifests(root_dir, excluded_package_roots):
        for product in parse_manifest(manifest):
            by_product.setdefault(product.product_name, product)

    matched = [
        by_product[name]
        for name in sorted(imports)
        if name in by_product and name not in QUILL_PROVIDED_IMPORTS
    ]
    package_lines = sorted({package_dependency_line(product) for product in matched})
    target_tokens = sorted({target_dependency_token(product) for product in matched})

    write_lines(args.package_dependencies_out, package_lines)
    write_lines(args.target_dependencies_out, target_tokens)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
