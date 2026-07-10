#!/usr/bin/env python3
"""Compute a content key for cached QuillUI lowered app source."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


EXCLUDED_DIRS = {
    ".build",
    ".git",
    ".quillui-build",
    ".swiftpm",
    "DerivedData",
    "node_modules",
    "xcuserdata",
}
EXCLUDED_FILES = {".DS_Store"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Hash app source and QuillUI lowering inputs for lowered-source cache reuse."
    )
    parser.add_argument("--root-dir", required=True, type=Path)
    parser.add_argument("--source-dir", required=True, type=Path)
    return parser.parse_args()


def update_with_file(digest: "hashlib._Hash", path: Path, root: Path, namespace: str) -> None:
    if not path.is_file() or path.name in EXCLUDED_FILES:
        return
    try:
        relative = path.resolve().relative_to(root.resolve())
    except ValueError:
        relative = path.resolve()
    try:
        data = path.read_bytes()
    except OSError:
        return
    digest.update(namespace.encode("utf-8"))
    digest.update(b"\0")
    digest.update(str(relative).encode("utf-8"))
    digest.update(b"\0")
    digest.update(str(len(data)).encode("utf-8"))
    digest.update(b":")
    digest.update(data)
    digest.update(b"\0")


def update_with_tree(digest: "hashlib._Hash", path: Path, namespace: str) -> None:
    if path.is_file():
        update_with_file(digest, path, path.parent, namespace)
        return
    if not path.is_dir():
        return
    for item in sorted(path.rglob("*")):
        try:
            relative = item.relative_to(path)
        except ValueError:
            continue
        if any(part in EXCLUDED_DIRS for part in relative.parts):
            continue
        if item.is_file():
            update_with_file(digest, item, path, namespace)


def vendored_app_source_fingerprint(root_dir: Path, source_dir: Path) -> tuple[Path, Path, str] | None:
    vendor_apps_dir = (root_dir / "vendor/apps").resolve()
    try:
        relative = source_dir.resolve().relative_to(vendor_apps_dir)
    except ValueError:
        return None
    if not relative.parts:
        return None

    app_root = vendor_apps_dir / relative.parts[0]
    fingerprint = app_root / ".quillui-vendor-source-fingerprint"
    if not fingerprint.is_file():
        return None

    source_subdir = Path(*relative.parts[1:]).as_posix() if len(relative.parts) > 1 else "."
    return app_root, fingerprint, source_subdir


def update_with_source_identity(digest: "hashlib._Hash", root_dir: Path, source_dir: Path) -> None:
    vendored_source = vendored_app_source_fingerprint(root_dir, source_dir)
    if vendored_source is None:
        update_with_tree(digest, source_dir, "source")
        return

    app_root, fingerprint, source_subdir = vendored_source
    app_relative = app_root.relative_to((root_dir / "vendor/apps").resolve()).as_posix()
    digest.update(b"source-vendored-app\0")
    digest.update(app_relative.encode("utf-8"))
    digest.update(b"\0")
    digest.update(source_subdir.encode("utf-8"))
    digest.update(b"\0")
    update_with_file(digest, fingerprint, app_root, "source-vendor-fingerprint")


def main() -> int:
    args = parse_args()
    root_dir = args.root_dir.resolve()
    source_dir = args.source_dir.resolve()
    digest = hashlib.sha256()
    digest.update(b"quillui-lowered-source-cache-v2\0")

    update_with_source_identity(digest, root_dir, source_dir)
    for relative in [
        "scripts/quillui-source-cache-key.py",
        "scripts/profiles/generic-swiftui.sh",
        "scripts/swiftpm-profile-lowered-source-cache.sh",
        "scripts/run-quill-source-lower.sh",
        "scripts/lower-swiftui-source-for-linux.sh",
        "scripts/lower-observable-for-swiftopenui.py",
        "scripts/ensure-swift-imports.sh",
        "scripts/run-quill-swiftui-lower.sh",
        "scripts/run-quill-appkit-lower.sh",
        "scripts/lower-mainactor-assignments-for-linux.py",
        "scripts/lower-extension-overrides-for-linux.py",
        "scripts/lower-objc-interop-for-linux.sh",
        "Sources/QuillSourceLowering",
        "Sources/quill-source-lower",
        "Sources/quill-lower-swiftui",
        "Sources/quill-lower-appkit",
    ]:
        update_with_tree(digest, root_dir / relative, "tool")

    print(digest.hexdigest())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
