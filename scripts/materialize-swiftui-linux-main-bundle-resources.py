#!/usr/bin/env python3
"""Materialize generated SwiftPM resources for Bundle.main lookups."""

from __future__ import annotations

import argparse
import collections
import filecmp
import shutil
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Copy generated target resources next to a Linux executable and add "
            "root aliases for unique basenames so Bundle.main.url(forResource:) "
            "matches Xcode main-bundle behavior for app resources."
        )
    )
    parser.add_argument("--resources-dir", required=True, type=Path)
    parser.add_argument("--bundle-dir", required=True, type=Path)
    return parser.parse_args()


def copy_if_safe(source: Path, destination: Path) -> bool:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        try:
            if filecmp.cmp(source, destination, shallow=False):
                return False
        except OSError:
            pass
        return False
    shutil.copy2(source, destination)
    return True


def main() -> int:
    args = parse_args()
    resources_dir = args.resources_dir.resolve()
    bundle_dir = args.bundle_dir.resolve()

    if not resources_dir.is_dir():
        print(f"No generated app resources to materialize: {resources_dir}")
        return 0
    if not bundle_dir.is_dir():
        raise SystemExit(f"--bundle-dir is not a directory: {bundle_dir}")

    files = sorted(path for path in resources_dir.rglob("*") if path.is_file())
    basename_counts = collections.Counter(path.name for path in files)
    copied = 0
    aliased = 0

    for path in files:
        relative = path.relative_to(resources_dir)
        copied += int(copy_if_safe(path, bundle_dir / relative))

    for path in files:
        if basename_counts[path.name] != 1:
            continue
        relative = path.relative_to(resources_dir)
        if len(relative.parts) == 1:
            continue
        aliased += int(copy_if_safe(path, bundle_dir / path.name))

    print(
        "Materialized generated SwiftUI Linux main-bundle resources: "
        f"{len(files)} files, {copied} copied, {aliased} root aliases"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
