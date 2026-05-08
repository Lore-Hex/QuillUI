#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable


@dataclass(frozen=True)
class Segment:
    start: int
    end: int

    @property
    def width(self) -> int:
        return self.end - self.start + 1

    @property
    def center(self) -> float:
        return (self.start + self.end) / 2


class Screenshot:
    def __init__(self, path: Path) -> None:
        probe = subprocess.run(
            ["identify", "-format", "%w %h %[mean] %[standard-deviation]", str(path)],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
        )
        width_text, height_text, mean_text, stddev_text = probe.stdout.split()
        self.path = path
        self.width = int(width_text)
        self.height = int(height_text)
        self.mean = float(mean_text)
        self.stddev = float(stddev_text)
        self._rgba = subprocess.run(
            ["convert", str(path), "rgba:-"],
            check=True,
            stdout=subprocess.PIPE,
        ).stdout

    def rgb(self, x: int, y: int) -> tuple[int, int, int]:
        offset = ((y * self.width) + x) * 4
        return self._rgba[offset], self._rgba[offset + 1], self._rgba[offset + 2]

    def brightness(self, x: int, y: int) -> int:
        return sum(self.rgb(x, y))

    def segments_at(
        self,
        y: int,
        x0: int,
        x1: int,
        predicate: Callable[[tuple[int, int, int]], bool],
        min_width: int,
    ) -> list[Segment]:
        segments: list[Segment] = []
        start: int | None = None

        for x in range(max(0, x0), min(self.width, x1)):
            matches = predicate(self.rgb(x, y))
            if matches and start is None:
                start = x
            elif not matches and start is not None:
                segment = Segment(start, x - 1)
                if segment.width >= min_width:
                    segments.append(segment)
                start = None

        if start is not None:
            segment = Segment(start, min(self.width, x1) - 1)
            if segment.width >= min_width:
                segments.append(segment)

        return segments


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def gray_line_pixel(rgb: tuple[int, int, int]) -> bool:
    total = sum(rgb)
    return 590 <= total <= 680 and max(rgb) - min(rgb) <= 12


def prompt_card_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return (
        235 <= red <= 250
        and 235 <= green <= 250
        and 235 <= blue <= 252
        and sum(rgb) < 745
    )


def content_bounds(image: Screenshot) -> tuple[int, int, int, int]:
    rows = [
        y
        for y in range(image.height)
        if any(image.brightness(x, y) > 90 for x in range(image.width))
    ]
    cols = [
        x
        for x in range(image.width)
        if any(image.brightness(x, y) > 90 for y in range(image.height))
    ]
    require(rows and cols, "Screenshot has no visible non-black content")
    return min(cols), max(cols), min(rows), max(rows)


def line_column_score(image: Screenshot, x: int, y0: int, y1: int) -> int:
    return sum(1 for y in range(y0, y1) if gray_line_pixel(image.rgb(x, y)))


def line_row_score(image: Screenshot, y: int, x0: int, x1: int) -> int:
    return sum(1 for x in range(x0, x1) if gray_line_pixel(image.rgb(x, y)))


def validate_quill_chat_landmarks(image: Screenshot) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(app_width >= 1000, f"Quill Chat window is too narrow: {app_width}px")
    require(520 <= app_height <= 720, f"Quill Chat window height is unexpected: {app_height}px")

    divider_search = range(left + 220, min(left + 450, right - 400))
    divider_x = max(
        divider_search,
        key=lambda x: line_column_score(image, x, top + 20, bottom - 40),
    )
    divider_score = line_column_score(image, divider_x, top + 20, bottom - 40)
    sidebar_width = divider_x - left
    require(
        285 <= sidebar_width <= 355 and divider_score >= app_height * 0.70,
        f"Quill Chat sidebar divider is missing or misplaced: x={divider_x}, score={divider_score}",
    )

    detail_left = divider_x + 1
    detail_width = right - detail_left + 1
    header_candidates = range(top + 60, min(top + 160, bottom))
    header_y = max(
        header_candidates,
        key=lambda y: line_row_score(image, y, detail_left, right + 1),
    )
    header_score = line_row_score(image, header_y, detail_left, right + 1)
    require(
        85 <= header_y - top <= 130 and header_score >= detail_width * 0.70,
        f"Quill Chat header divider is missing or misplaced: y={header_y}, score={header_score}",
    )

    prompt_row = -1
    prompt_segments: list[Segment] = []
    for y in range(header_y + 120, min(bottom - 120, header_y + 360)):
        segments = image.segments_at(y, detail_left, right + 1, prompt_card_pixel, min_width=110)
        if len(segments) >= 4:
            prompt_row = y
            prompt_segments = segments[:4]
            break

    require(prompt_segments, "Quill Chat prompt card row was not detected")
    require(
        all(120 <= segment.width <= 190 for segment in prompt_segments),
        f"Quill Chat prompt card widths are unexpected: {[segment.width for segment in prompt_segments]}",
    )
    require(
        prompt_segments[0].start >= detail_left + 40 and prompt_segments[-1].end <= right - 40,
        f"Quill Chat prompt cards are not centered in detail pane: {prompt_segments}",
    )

    composer_segment: Segment | None = None
    composer_y = -1
    for y in range(max(prompt_row + 90, bottom - 130), max(prompt_row + 91, bottom - 15)):
        candidates = image.segments_at(y, detail_left, right + 1, gray_line_pixel, min_width=500)
        if candidates:
            segment = max(candidates, key=lambda item: item.width)
            if composer_segment is None or segment.width > composer_segment.width:
                composer_segment = segment
                composer_y = y

    require(composer_segment is not None, "Quill Chat composer border was not detected")
    require(
        composer_segment.width >= 650,
        f"Quill Chat composer is too narrow: {composer_segment.width}px",
    )
    require(
        detail_left + 5 <= composer_segment.start <= detail_left + 80,
        f"Quill Chat composer starts at an unexpected x: {composer_segment.start}",
    )

    return (
        "Quill Chat landmarks: "
        f"app={app_width}x{app_height}, "
        f"sidebar={sidebar_width}px, "
        f"header={header_y - top}px, "
        f"prompt_row={prompt_row}px, "
        f"cards={prompt_segments[0].start}-{prompt_segments[-1].end}, "
        f"composer={composer_segment.width}px@{composer_y}"
    )


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: verify-gtk-screenshot.py SCREENSHOT_PATH PRODUCT", file=sys.stderr)
        return 64

    path = Path(sys.argv[1])
    product = sys.argv[2]
    if not path.exists() or path.stat().st_size == 0:
        raise SystemExit("Screenshot was not created")

    image = Screenshot(path)
    require(
        image.width >= 900 and image.height >= 600,
        f"Screenshot is unexpectedly small: {image.width}x{image.height}",
    )
    require(image.mean > 1000, f"Screenshot appears blank or near-black: mean={image.mean}")
    require(
        image.stddev > 250,
        f"Screenshot appears visually flat: standard-deviation={image.stddev:.1f}",
    )

    print(
        f"Visual smoke screenshot: {path} "
        f"({image.width}x{image.height}, mean={image.mean:.1f}, stddev={image.stddev:.1f})"
    )

    if product == "quill-chat-linux":
        print(validate_quill_chat_landmarks(image))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
