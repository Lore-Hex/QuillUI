#!/usr/bin/env python3
"""Run the backend-screenshot parity validators LOCALLY, without ImageMagick.

`scripts/verify-backend-screenshot.py` shells out to ImageMagick (`identify` +
`convert`) to read pixels, which CI has but many dev machines do not. This
wrapper decodes the PNG with a small pure-stdlib decoder and monkeypatches the
real `Screenshot` class, so you can develop and calibrate parity validators
(e.g. the Enchanted empty-state landmark gate) on a laptop and then trust CI's
ImageMagick path for the authoritative run.

Usage (mirrors the real script's CLI):
    python3 scripts/verify-backend-screenshot-local.py SCREENSHOT.png PRODUCT

CAVEAT: this decoder is an approximation of ImageMagick's RGBA output (it does
NOT apply ICC/gamma transforms). It is intended for predicate calibration and
catching gross failures with WIDE-MARGIN predicates — it is NOT a substitute
for the CI run. Keep validator thresholds well clear of the observed values so
small decoder-vs-ImageMagick differences cannot flip a landmark.

Handles 8-bit truecolor (RGB / RGBA), non-interlaced PNGs — what the
`linux-backend-qa` artifacts are.
"""
import importlib.util
import struct
import sys
import zlib
from pathlib import Path


def decode_png(path):
    data = Path(path).read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path}: not a PNG")
    pos = 8
    width = height = bit_depth = color_type = None
    idat = bytearray()
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        chunk_type = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type = struct.unpack(">IIBB", chunk[:10])
        elif chunk_type == b"IDAT":
            idat += chunk
        elif chunk_type == b"IEND":
            break
        pos += 12 + length
    if bit_depth != 8 or color_type not in (2, 6):
        raise SystemExit(
            f"{path}: unsupported PNG (bit_depth={bit_depth}, color_type={color_type}); "
            "only 8-bit RGB/RGBA non-interlaced is handled"
        )
    bpp = 3 if color_type == 2 else 4
    raw = zlib.decompress(bytes(idat))
    stride = width * bpp
    out = bytearray(width * height * bpp)
    prev = bytearray(stride)
    p = 0
    for y in range(height):
        ftype = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        if ftype == 1:  # Sub
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif ftype == 2:  # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif ftype == 3:  # Average
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif ftype == 4:  # Paeth
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return width, height, bpp, out


def load_verify_module():
    here = Path(__file__).resolve().parent
    spec = importlib.util.spec_from_file_location(
        "verify_backend_screenshot", here / "verify-backend-screenshot.py"
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules["verify_backend_screenshot"] = module  # needed for @dataclass
    spec.loader.exec_module(module)
    return module


def main(argv):
    if len(argv) != 3:
        print("Usage: verify-backend-screenshot-local.py SCREENSHOT_PATH PRODUCT", file=sys.stderr)
        return 64
    path, product = argv[1], argv[2]
    vbs = load_verify_module()

    class LocalScreenshot(vbs.Screenshot):
        def __init__(self, screenshot_path):
            w, h, bpp, px = decode_png(screenshot_path)
            self.path = Path(screenshot_path)
            self.width = w
            self.height = h
            self._bpp = bpp
            self._px = px
            # mean/stddev are only used by main()'s blank/flat guards; approximate.
            total = sum(px[i] for i in range(0, len(px), max(1, bpp)))
            n = max(1, len(px) // max(1, bpp))
            self.mean = (total / n) * 257.0  # scale 0-255 -> ImageMagick-ish 0-65535
            self.stddev = 4000.0

        def rgb(self, x, y):
            o = (y * self.width + x) * self._bpp
            return (self._px[o], self._px[o + 1], self._px[o + 2])

    vbs.Screenshot = LocalScreenshot
    saved = sys.argv
    try:
        sys.argv = ["verify-backend-screenshot.py", path, product]
        return vbs.main()
    finally:
        sys.argv = saved


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
