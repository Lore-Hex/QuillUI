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


def local_package_manifests(root_dir: Path) -> list[Path]:
    manifests: list[Path] = []
    for relative_root in (".upstream", "vendor/apps", "third_party"):
        base = root_dir / relative_root
        if not base.is_dir():
            continue
        manifests.extend(sorted(base.rglob("Package.swift")))
    return manifests


def parse_manifest(manifest: Path) -> list[LocalProduct]:
    text = manifest.read_text(encoding="utf-8", errors="ignore")
    package_match = PACKAGE_NAME_RE.search(text)
    if package_match is None:
        return []

    package_name = package_match.group(1)
    package_path = manifest.parent.resolve()
    products: list[LocalProduct] = []
    for product_name in sorted(set(PRODUCT_RE.findall(text))):
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

    imports = swift_imports(source_dir)
    by_product: dict[str, LocalProduct] = {}
    for manifest in local_package_manifests(root_dir):
        for product in parse_manifest(manifest):
            by_product.setdefault(product.product_name, product)

    matched = [by_product[name] for name in sorted(imports) if name in by_product]
    package_lines = sorted({package_dependency_line(product) for product in matched})
    target_tokens = sorted({target_dependency_token(product) for product in matched})

    write_lines(args.package_dependencies_out, package_lines)
    write_lines(args.target_dependencies_out, target_tokens)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
