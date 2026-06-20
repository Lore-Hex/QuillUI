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


def self_test() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "target.png"
        _write_test_png(path)
        x, y = quill_chat_new_completion(path)
    if not (84 <= x <= 87 and 37 <= y <= 40):
        print(f"unexpected self-test target: {x} {y}", file=sys.stderr)
        return 1
    return 0


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[1] == "--self-test":
        return self_test()
    if len(argv) != 3 or argv[1] != "quill-chat-new-completion":
        print(
            "Usage: quillui-image-click-target.py quill-chat-new-completion SCREENSHOT.png",
            file=sys.stderr,
        )
        return 64

    try:
        x, y = quill_chat_new_completion(Path(argv[2]))
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 1

    print(f"{x} {y}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
