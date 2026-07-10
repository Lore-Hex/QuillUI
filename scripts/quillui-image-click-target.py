#!/usr/bin/env python3
"""Return robust click targets from backend QA screenshots.

The interaction drivers use this for targets whose exact pixel position varies
with renderer, font metrics, and package/runtime chrome. Keep the detector
stdlib-only so it works in local checkouts that do not have ImageMagick helpers
other than the CI screenshot capture path.
"""

from __future__ import annotations

import binascii
import importlib.util
import struct
import sys
import tempfile
import zlib
from pathlib import Path


def _load_decode_png():
    decoder_path = Path(__file__).with_name("verify-backend-screenshot-local.py")
    spec = importlib.util.spec_from_file_location("quillui_verify_backend_screenshot_local", decoder_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load PNG decoder from {decoder_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.decode_png


decode_png = _load_decode_png()


def _rgb_at(pixels: bytearray, width: int, bpp: int, x: int, y: int) -> tuple[int, int, int]:
    offset = (y * width + x) * bpp
    return pixels[offset], pixels[offset + 1], pixels[offset + 2]


def _is_blue_action_text(r: int, g: int, b: int) -> bool:
    return b >= 135 and r <= 170 and g <= 170 and (b - r) >= 35 and (b - g) >= 25


def _find_colored_text_center(
    *,
    width: int,
    height: int,
    bpp: int,
    pixels: bytearray,
    x_min_ratio: float,
    x_max_ratio: float,
    y_min_ratio: float,
    y_max_ratio: float,
    minimum_pixels: int,
) -> tuple[int, int] | None:
    x_min = max(0, min(width - 1, int(width * x_min_ratio)))
    x_max = max(x_min + 1, min(width, int(width * x_max_ratio)))
    y_min = max(0, min(height - 1, int(height * y_min_ratio)))
    y_max = max(y_min + 1, min(height, int(height * y_max_ratio)))

    xs: list[int] = []
    ys: list[int] = []
    for y in range(y_min, y_max):
        for x in range(x_min, x_max):
            if _is_blue_action_text(*_rgb_at(pixels, width, bpp, x, y)):
                xs.append(x)
                ys.append(y)

    if len(xs) < minimum_pixels:
        return None

    return round((min(xs) + max(xs)) / 2), round((min(ys) + max(ys)) / 2)


def quill_chat_new_completion(path: Path) -> tuple[int, int]:
    width, height, bpp, pixels = decode_png(path)
    # The Mac-reference Completions panel puts the link-colored "New Completion"
    # action in the panel's upper-right quadrant. Restricting the scan there
    # avoids the center Quill wordmark and the left "Completions" title.
    point = _find_colored_text_center(
        width=width,
        height=height,
        bpp=bpp,
        pixels=pixels,
        x_min_ratio=0.62,
        x_max_ratio=0.80,
        y_min_ratio=0.30,
        y_max_ratio=0.47,
        minimum_pixels=30,
    )
    if point is None:
        raise RuntimeError(f"{path}: New Completion action was not detected")
    return point


def _dark_components(
    *,
    width: int,
    height: int,
    bpp: int,
    pixels: bytearray,
    x_min_ratio: float,
    x_max_ratio: float,
    y_min_ratio: float,
    y_max_ratio: float,
) -> list[tuple[int, int, int, int, int]]:
    x_min = max(0, min(width - 1, int(width * x_min_ratio)))
    x_max = max(x_min + 1, min(width, int(width * x_max_ratio)))
    y_min = max(0, min(height - 1, int(height * y_min_ratio)))
    y_max = max(y_min + 1, min(height, int(height * y_max_ratio)))
    dark: set[tuple[int, int]] = set()
    for y in range(y_min, y_max):
        for x in range(x_min, x_max):
            r, g, b = _rgb_at(pixels, width, bpp, x, y)
            if r < 95 and g < 105 and b < 115:
                dark.add((x, y))

    components: list[tuple[int, int, int, int, int]] = []
    while dark:
        start = dark.pop()
        stack = [start]
        xs = [start[0]]
        ys = [start[1]]
        while stack:
            x, y = stack.pop()
            for nx in (x - 1, x, x + 1):
                for ny in (y - 1, y, y + 1):
                    if (nx, ny) in dark:
                        dark.remove((nx, ny))
                        stack.append((nx, ny))
                        xs.append(nx)
                        ys.append(ny)
        components.append((min(xs), min(ys), max(xs), max(ys), len(xs)))
    return components


def quill_chat_first_completion_delete(path: Path) -> tuple[int, int]:
    width, height, bpp, pixels = decode_png(path)
    components = _dark_components(
        width=width,
        height=height,
        bpp=bpp,
        pixels=pixels,
        x_min_ratio=0.65,
        x_max_ratio=0.78,
        y_min_ratio=0.36,
        y_max_ratio=0.52,
    )
    candidates = []
    for x0, y0, x1, y1, count in components:
        component_width = x1 - x0 + 1
        component_height = y1 - y0 + 1
        if 8 <= component_width <= 28 and 8 <= component_height <= 28 and count >= 20:
            center_x = round((x0 + x1) / 2)
            center_y = round((y0 + y1) / 2)
            candidates.append((center_y, center_x, x0, y0, x1, y1, count))

    if not candidates:
        raise RuntimeError(f"{path}: first completion delete action was not detected")

    first_row_y = min(candidate[0] for candidate in candidates)
    first_row_candidates = [candidate for candidate in candidates if candidate[0] <= first_row_y + 16]
    _, center_x, _, _, _, _, _ = max(first_row_candidates, key=lambda candidate: candidate[1])
    center_y = round(sum(candidate[0] for candidate in first_row_candidates) / len(first_row_candidates))
    return center_x, center_y


def _png_chunk(kind: bytes, payload: bytes) -> bytes:
    checksum = binascii.crc32(kind)
    checksum = binascii.crc32(payload, checksum) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", checksum)


def _write_test_png(path: Path) -> None:
    width = 120
    height = 90
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            if 78 <= x <= 92 and 34 <= y <= 42:
                rows.extend((70, 95, 220))
            else:
                rows.extend((242, 242, 242))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    data = (
        b"\x89PNG\r\n\x1a\n"
        + _png_chunk(b"IHDR", ihdr)
        + _png_chunk(b"IDAT", zlib.compress(bytes(rows)))
        + _png_chunk(b"IEND", b"")
    )
    path.write_bytes(data)


def _write_delete_test_png(path: Path) -> None:
    width = 200
    height = 160
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            if (132 <= x <= 141 and 64 <= y <= 73) or (148 <= x <= 157 and 64 <= y <= 73):
                rows.extend((64, 68, 72))
            else:
                rows.extend((244, 244, 244))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    data = (
        b"\x89PNG\r\n\x1a\n"
        + _png_chunk(b"IHDR", ihdr)
        + _png_chunk(b"IDAT", zlib.compress(bytes(rows)))
        + _png_chunk(b"IEND", b"")
    )
    path.write_bytes(data)


def self_test() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "target.png"
        _write_test_png(path)
        x, y = quill_chat_new_completion(path)
    if not (84 <= x <= 87 and 37 <= y <= 40):
        print(f"unexpected self-test target: {x} {y}", file=sys.stderr)
        return 1
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "delete.png"
        _write_delete_test_png(path)
        x, y = quill_chat_first_completion_delete(path)
    if not (152 <= x <= 153 and 68 <= y <= 69):
        print(f"unexpected delete self-test target: {x} {y}", file=sys.stderr)
        return 1
    return 0


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[1] == "--self-test":
        return self_test()
    if len(argv) != 3 or argv[1] not in {"quill-chat-new-completion", "quill-chat-first-completion-delete"}:
        print(
            "Usage: quillui-image-click-target.py TARGET SCREENSHOT.png",
            file=sys.stderr,
        )
        return 64

    try:
        if argv[1] == "quill-chat-new-completion":
            x, y = quill_chat_new_completion(Path(argv[2]))
        else:
            x, y = quill_chat_first_completion_delete(Path(argv[2]))
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 1

    print(f"{x} {y}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
