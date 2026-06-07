#!/usr/bin/env python3
"""Copy Swift app resources into a generated Linux SwiftPM target.

The generated app build keeps upstream Swift sources unchanged, but Linux
cannot consume Apple's compiled asset catalogs. This helper extracts image
assets from `.xcassets` into stable file names such as `logo.png` so
SwiftUI-shaped source like `Image("logo")` can resolve them at runtime.
"""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path


IMAGE_EXTENSIONS = {
    ".png",
    ".jpg",
    ".jpeg",
    ".webp",
    ".gif",
    ".bmp",
    ".tiff",
    ".tif",
    ".svg",
}

RESOURCE_EXTENSIONS = IMAGE_EXTENSIONS | {
    ".json",
    ".plist",
    ".strings",
    ".xcstrings",
    ".html",
    ".css",
    ".js",
    ".opml",
    ".rtf",
    ".wav",
    ".mp3",
    ".m4a",
    ".ttf",
    ".otf",
}

SKIP_DIRECTORIES = {
    ".build",
    ".git",
    ".swiftpm",
    "DerivedData",
    "build",
    "xcuserdata",
}


def is_inside_asset_catalog(path: Path) -> bool:
    return any(part.endswith(".xcassets") for part in path.parts)


def is_skipped(path: Path) -> bool:
    return any(part in SKIP_DIRECTORIES for part in path.parts)


def parse_scale(value: object) -> float:
    if not isinstance(value, str):
        return 1.0
    if value.endswith("x"):
        value = value[:-1]
    try:
        return float(value)
    except ValueError:
        return 1.0


def idiom_rank(value: object) -> int:
    if not isinstance(value, str):
        return 0
    return {
        "universal": 5,
        "mac": 4,
        "ipad": 3,
        "iphone": 2,
    }.get(value, 1)


def uniqued_destination(path: Path) -> Path:
    if not path.exists():
        return path

    stem = path.stem
    suffix = path.suffix
    parent = path.parent
    index = 2
    while True:
        candidate = parent / f"{stem}-{index}{suffix}"
        if not candidate.exists():
            return candidate
        index += 1


def copy_file(source: Path, destination: Path) -> bool:
    destination = uniqued_destination(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    return True


def asset_catalog_directories(source: Path) -> list[Path]:
    return sorted(path for path in source.rglob("*.xcassets") if path.is_dir() and not is_skipped(path))


def choose_imageset_file(imageset: Path) -> Path | None:
    contents_path = imageset / "Contents.json"
    if not contents_path.is_file():
        return None

    try:
        payload = json.loads(contents_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None

    candidates: list[tuple[tuple[int, float, str], Path]] = []
    for entry in payload.get("images", []):
        if not isinstance(entry, dict):
            continue
        filename = entry.get("filename")
        if not isinstance(filename, str) or not filename:
            continue
        image_path = imageset / filename
        if not image_path.is_file():
            continue
        key = (
            idiom_rank(entry.get("idiom")),
            parse_scale(entry.get("scale")),
            filename,
        )
        candidates.append((key, image_path))

    if not candidates:
        return None

    return sorted(candidates, key=lambda item: item[0], reverse=True)[0][1]


def copy_asset_catalog_images(source: Path, destination: Path) -> int:
    copied = 0
    for catalog in asset_catalog_directories(source):
        for imageset in sorted(catalog.rglob("*.imageset")):
            if not imageset.is_dir():
                continue
            selected = choose_imageset_file(imageset)
            if selected is None:
                continue
            asset_name = imageset.name.removesuffix(".imageset")
            copied += int(copy_file(selected, destination / f"{asset_name}{selected.suffix.lower()}"))
    return copied


def copy_plain_resources(source: Path, destination: Path) -> int:
    copied = 0
    for path in sorted(source.rglob("*")):
        if not path.is_file():
            continue
        if is_skipped(path.relative_to(source)):
            continue
        if is_inside_asset_catalog(path.relative_to(source)):
            continue
        if path.suffix.lower() not in RESOURCE_EXTENSIONS:
            continue

        copied += int(copy_file(path, destination / path.relative_to(source)))
    return copied


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", required=True)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()

    source = Path(args.source_dir).resolve()
    destination = Path(args.output_dir).resolve()
    if not source.is_dir():
        parser.error(f"--source-dir is not a directory: {source}")

    if destination.exists():
        shutil.rmtree(destination)

    plain_count = copy_plain_resources(source, destination)
    asset_count = copy_asset_catalog_images(source, destination)
    total = plain_count + asset_count

    if total == 0 and destination.exists():
        shutil.rmtree(destination)

    print(
        f"Copied generated SwiftUI Linux resources: {total} "
        f"({plain_count} plain, {asset_count} asset-catalog images)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
