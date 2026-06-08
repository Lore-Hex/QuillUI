#!/usr/bin/env python3
import re
import sys
from pathlib import Path


IMPORT_TO_PRODUCT = {
    "AppKit": "AppKit",
    "Cocoa": "Cocoa",
    "CoreGraphics": "CoreGraphics",
    "Security": "Security",
}


def imported_products(package_dir: Path) -> list[str]:
    products: set[str] = set()
    for swift_file in sorted((package_dir / "Sources").rglob("*.swift")):
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
            output.append(line)

    return "\n".join(output) + ("\n" if manifest.endswith("\n") else "")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: patch-telegram-package-manifest.py PACKAGE_DIR QUILLUI_ROOT")

    package_dir = Path(sys.argv[1])
    quill_root = sys.argv[2]
    manifest_path = package_dir / "Package.swift"
    products = imported_products(package_dir)
    if not products:
        return

    manifest = manifest_path.read_text(encoding="utf-8")
    manifest = insert_quill_dependency(manifest, quill_root)
    manifest = insert_target_products(manifest, products)
    manifest_path.write_text(manifest, encoding="utf-8")


if __name__ == "__main__":
    main()
