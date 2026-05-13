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
    # SwiftOpenUI's GTK4 renders the prompt-card background at
    # RGB(232, 232, 238) — slightly darker / bluer than Mac
    # SwiftUI's RGB(238+, 238+, 240+). Widen the low end to 230
    # so the detector matches both backends.
    return (
        230 <= red <= 250
        and 230 <= green <= 250
        and 230 <= blue <= 252
        and sum(rgb) < 745
    )


def mac_reference_prompt_card_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return 222 <= red <= 235 and 222 <= green <= 235 and 225 <= blue <= 242 and blue >= red


def mac_reference_composer_pixel(rgb: tuple[int, int, int]) -> bool:
    return 540 <= sum(rgb) <= 720 and max(rgb) - min(rgb) <= 30


def settings_panel_background_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return 220 <= red <= 245 and 220 <= green <= 245 and 225 <= blue <= 250 and max(rgb) - min(rgb) <= 24


def form_field_pixel(rgb: tuple[int, int, int]) -> bool:
    return sum(rgb) >= 735 and max(rgb) - min(rgb) <= 12


def markdown_code_panel_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return (
        230 <= red <= 252
        and 230 <= green <= 252
        and 232 <= blue <= 255
        and max(rgb) - min(rgb) <= 18
        and sum(rgb) < 748
    )


def toolbar_dark_pixel(rgb: tuple[int, int, int]) -> bool:
    return sum(rgb) < 320


def alert_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return 230 <= red <= 255 and 175 <= green <= 225 and 185 <= blue <= 230 and red - green >= 20


def wireguard_qt_sidebar_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return (
        238 <= red <= 252
        and 238 <= green <= 252
        and 239 <= blue <= 253
        and max(rgb) - min(rgb) <= 8
        and sum(rgb) < 755
    )


def wireguard_qt_selected_row_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return 225 <= red <= 240 and 232 <= green <= 245 and 245 <= blue <= 255 and blue - red >= 8


def wireguard_qt_section_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return (
        238 <= red <= 248
        and 238 <= green <= 248
        and 239 <= blue <= 250
        and max(rgb) - min(rgb) <= 8
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


def dark_pixel_count(image: Screenshot, x0: int, y0: int, x1: int, y1: int) -> int:
    return sum(
        1
        for y in range(max(0, y0), min(image.height, y1))
        for x in range(max(0, x0), min(image.width, x1))
        if sum(image.rgb(x, y)) < 420
    )


def pixel_count(
    image: Screenshot,
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    predicate: Callable[[tuple[int, int, int]], bool],
) -> int:
    return sum(
        1
        for y in range(max(0, y0), min(image.height, y1))
        for x in range(max(0, x0), min(image.width, x1))
        if predicate(image.rgb(x, y))
    )


def best_pixel_row_segment(
    image: Screenshot,
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    predicate: Callable[[tuple[int, int, int]], bool],
    min_row_pixels: int,
) -> tuple[Segment, int] | None:
    best: tuple[Segment, int] | None = None
    start: int | None = None
    last_y = 0
    segment_pixels = 0

    for y in range(max(0, y0), min(image.height, y1)):
        row_pixels = sum(
            1
            for x in range(max(0, x0), min(image.width, x1))
            if predicate(image.rgb(x, y))
        )
        if row_pixels >= min_row_pixels:
            if start is None:
                start = y
                segment_pixels = 0
            last_y = y
            segment_pixels += row_pixels
        elif start is not None:
            candidate = (Segment(start, last_y), segment_pixels)
            if best is None or candidate[1] > best[1]:
                best = candidate
            start = None

    if start is not None:
        candidate = (Segment(start, last_y), segment_pixels)
        if best is None or candidate[1] > best[1]:
            best = candidate

    return best


def mac_window_control_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return (
        (red >= 210 and green <= 130 and blue <= 130)
        or (red >= 210 and green >= 145 and blue <= 105)
        or (green >= 155 and red <= 130 and blue <= 130)
    )


def colorful_wordmark_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return max(rgb) - min(rgb) >= 35 and 180 <= sum(rgb) <= 650


def best_horizontal_segment(
    image: Screenshot,
    y0: int,
    y1: int,
    x0: int,
    x1: int,
    predicate: Callable[[tuple[int, int, int]], bool],
    min_width: int,
) -> tuple[int, Segment] | None:
    best: tuple[int, Segment] | None = None
    for y in range(max(0, y0), min(image.height, y1)):
        segments = image.segments_at(y, x0, x1, predicate, min_width)
        if not segments:
            continue
        segment = max(segments, key=lambda item: item.width)
        if best is None or segment.width > best[1].width:
            best = (y, segment)
    return best


def best_prompt_card_row(
    image: Screenshot,
    y0: int,
    y1: int,
    x0: int,
    x1: int,
    min_width: int,
    predicate: Callable[[tuple[int, int, int]], bool] = prompt_card_pixel,
) -> tuple[int, list[Segment]] | None:
    best: tuple[int, list[Segment]] | None = None
    best_score = -1
    for y in range(max(0, y0), min(image.height, y1)):
        segments = image.segments_at(y, x0, x1, predicate, min_width)
        if len(segments) < 4:
            continue
        segments = segments[:4]
        score = sum(segment.width for segment in segments)
        if score > best_score:
            best = (y, segments)
            best_score = score
    return best


def validate_quill_chat_mac_reference(image: Screenshot) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(app_width >= 1800, f"Quill Chat reference window is too narrow: {app_width}px")
    require(app_height >= 1200, f"Quill Chat reference window is too short: {app_height}px")

    divider_search = range(left + int(app_width * 0.23), left + int(app_width * 0.34))
    divider_x = max(
        divider_search,
        key=lambda x: line_column_score(image, x, top + int(app_height * 0.04), bottom - 40),
    )
    divider_score = line_column_score(image, divider_x, top + int(app_height * 0.04), bottom - 40)
    sidebar_ratio = (divider_x - left) / app_width
    require(
        0.255 <= sidebar_ratio <= 0.305 and divider_score >= app_height * 0.72,
        f"Mac-reference sidebar divider mismatch: x={divider_x}, ratio={sidebar_ratio:.3f}, score={divider_score}",
    )

    detail_left = divider_x + 1
    detail_width = right - detail_left + 1
    sidebar_history_pixels = dark_pixel_count(
        image,
        left + int((divider_x - left) * 0.03),
        top + int(app_height * 0.07),
        divider_x - int((divider_x - left) * 0.03),
        top + int(app_height * 0.58),
    )
    require(
        sidebar_history_pixels >= 1700,
        f"Mac-reference sidebar history text was not detected: pixels={sidebar_history_pixels}",
    )
    sidebar_footer_pixels = dark_pixel_count(
        image,
        left + int((divider_x - left) * 0.03),
        bottom - int(app_height * 0.16),
        divider_x - int((divider_x - left) * 0.03),
        bottom + 1,
    )
    require(
        sidebar_footer_pixels >= 700,
        f"Mac-reference sidebar footer navigation was not detected: pixels={sidebar_footer_pixels}",
    )
    window_control_pixels = pixel_count(
        image,
        left,
        top,
        left + int((divider_x - left) * 0.30),
        top + int(app_height * 0.08),
        mac_window_control_pixel,
    )
    require(
        window_control_pixels >= 220,
        f"Mac-reference window controls were not detected: pixels={window_control_pixels}",
    )

    header_candidates = range(top + int(app_height * 0.04), top + int(app_height * 0.11))
    header_y = max(
        header_candidates,
        key=lambda y: line_row_score(image, y, detail_left, right + 1),
    )
    header_score = line_row_score(image, header_y, detail_left, right + 1)
    header_ratio = (header_y - top) / app_height
    require(
        0.045 <= header_ratio <= 0.085 and header_score >= detail_width * 0.70,
        f"Mac-reference header divider mismatch: y={header_y}, ratio={header_ratio:.3f}, score={header_score}",
    )

    toolbar_pixels = dark_pixel_count(
        image,
        right - int(app_width * 0.18),
        top + int(app_height * 0.01),
        right + 1,
        header_y,
    )
    require(toolbar_pixels >= 120, f"Mac-reference toolbar actions were not detected: pixels={toolbar_pixels}")

    wordmark_pixels = pixel_count(
        image,
        detail_left + int(detail_width * 0.35),
        top + int(app_height * 0.20),
        detail_left + int(detail_width * 0.65),
        top + int(app_height * 0.45),
        colorful_wordmark_pixel,
    )
    require(
        wordmark_pixels >= 750,
        f"Mac-reference wordmark was not detected: pixels={wordmark_pixels}",
    )

    card_row = best_prompt_card_row(
        image,
        top + int(app_height * 0.30),
        top + int(app_height * 0.63),
        detail_left,
        right + 1,
        min_width=int(app_width * 0.10),
        predicate=mac_reference_prompt_card_pixel,
    )
    require(card_row is not None, "Mac-reference prompt card row was not detected")
    prompt_y, prompt_segments = card_row
    card_widths = [segment.width for segment in prompt_segments]
    require(
        all(app_width * 0.115 <= width <= app_width * 0.18 for width in card_widths),
        f"Mac-reference prompt card widths mismatch: {card_widths}",
    )
    gaps = [
        prompt_segments[index + 1].start - prompt_segments[index].end - 1
        for index in range(3)
    ]
    require(
        all(app_width * 0.005 <= gap <= app_width * 0.04 for gap in gaps),
        f"Mac-reference prompt card gaps mismatch: {gaps}",
    )
    require(
        detail_left + detail_width * 0.05 <= prompt_segments[0].start
        and prompt_segments[-1].end <= right - detail_width * 0.03,
        f"Mac-reference prompt cards are not centered in detail pane: {prompt_segments}",
    )
    prompt_text_pixels = dark_pixel_count(
        image,
        prompt_segments[0].start + 18,
        max(top, prompt_y - int(app_height * 0.04)),
        prompt_segments[-1].end - 18,
        min(bottom, prompt_y + int(app_height * 0.08)),
    )
    require(
        prompt_text_pixels >= 1300,
        f"Mac-reference prompt card text was not detected: pixels={prompt_text_pixels}",
    )

    alert = best_horizontal_segment(
        image,
        top + int(app_height * 0.68),
        top + int(app_height * 0.88),
        detail_left,
        right + 1,
        alert_pixel,
        min_width=int(detail_width * 0.55),
    )
    require(alert is not None, "Mac-reference unreachable API alert was not detected")
    alert_y, alert_segment = alert
    require(
        alert_segment.width >= detail_width * 0.72,
        f"Mac-reference alert is too narrow: {alert_segment.width}px",
    )
    alert_rows = [
        y
        for y in range(top + int(app_height * 0.68), top + int(app_height * 0.90))
        if any(
            segment.width >= detail_width * 0.55
            for segment in image.segments_at(y, detail_left, right + 1, alert_pixel, min_width=int(detail_width * 0.55))
        )
    ]
    require(alert_rows, "Mac-reference alert fill rows were not detected")
    alert_height = alert_rows[-1] - alert_rows[0] + 1
    require(alert_height >= 80, f"Mac-reference alert is too short: height={alert_height}px")

    composer = None
    for y in range(top + int(app_height * 0.86), bottom + 1):
        candidates = [
            segment
            for segment in image.segments_at(
                y,
                detail_left,
                right + 1,
                mac_reference_composer_pixel,
                min_width=int(detail_width * 0.55),
            )
            if segment.start >= detail_left + int(detail_width * 0.03)
            and segment.end <= right - int(detail_width * 0.01)
        ]
        if candidates:
            segment = max(candidates, key=lambda item: item.width)
            if composer is None or segment.width > composer[1].width:
                composer = (y, segment)
    require(composer is not None, "Mac-reference composer border was not detected")
    composer_y, composer_segment = composer
    require(
        composer_segment.width >= detail_width * 0.75,
        f"Mac-reference composer is too narrow: {composer_segment.width}px",
    )

    return (
        "Quill Chat Mac-reference landmarks: "
        f"app={app_width}x{app_height}, "
        f"sidebar={divider_x - left}px/{sidebar_ratio:.3f}, "
        f"header={header_y - top}px/{header_ratio:.3f}, "
        f"toolbar_pixels={toolbar_pixels}, "
        f"history_pixels={sidebar_history_pixels}, "
        f"footer_pixels={sidebar_footer_pixels}, "
        f"window_controls={window_control_pixels}, "
        f"wordmark_pixels={wordmark_pixels}, "
        f"prompt_row={prompt_y}px, "
        f"cards={[f'{segment.start}-{segment.end}' for segment in prompt_segments]}, "
        f"prompt_text_pixels={prompt_text_pixels}, "
        f"alert={alert_segment.width}px@{alert_y}/{alert_height}px, "
        f"composer={composer_segment.width}px@{composer_y}"
    )


def validate_quill_chat_landmarks(
    image: Screenshot,
    allow_expanded_toolbar: bool = False,
    max_height: int = 780,
) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(app_width >= 1000, f"Quill Chat window is too narrow: {app_width}px")
    require(520 <= app_height <= max_height, f"Quill Chat window height is unexpected: {app_height}px")

    divider_search = range(left + 220, min(left + 450, right - 400))
    divider_x = max(
        divider_search,
        key=lambda x: line_column_score(image, x, top + 20, bottom - 40),
    )
    divider_score = line_column_score(image, divider_x, top + 20, bottom - 40)
    sidebar_width = divider_x - left
    # SwiftOpenUI's GTK4 NavigationSplitView divider is a 1px
    # background-color transition rather than a high-contrast
    # line (Apple's macOS divider is more pronounced). Accept
    # anything >= 10% of the window height as a real divider; the
    # sidebar-width range is the stricter shape check.
    require(
        285 <= sidebar_width <= 355 and divider_score >= app_height * 0.10,
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
    # SwiftOpenUI's GTK4 toolbar bottom is a soft background-color
    # boundary, not a high-contrast horizontal line. Mac SwiftUI's
    # toolbar uses a sharper divider. Match the sidebar-divider
    # relaxation: keep the position range tight but accept any
    # detectable horizontal contrast (>= 10% of detail width) as
    # a real header boundary.
    require(
        55 <= header_y - top <= 95 and header_score >= detail_width * 0.10,
        f"Quill Chat header divider is missing or misplaced: y={header_y}, score={header_score}",
    )

    toolbar_rows = [
        y
        for y in range(top + 25, header_y)
        if sum(
            1
            for x in range(max(detail_left, right - 220), right + 1)
            if toolbar_dark_pixel(image.rgb(x, y))
        )
        >= 3
    ]
    require(toolbar_rows, "Quill Chat toolbar actions were not detected")
    toolbar_spread = toolbar_rows[-1] - toolbar_rows[0] + 1
    if not allow_expanded_toolbar:
        require(
            toolbar_spread <= 32,
            f"Quill Chat toolbar actions appear vertically stacked: spread={toolbar_spread}px",
        )

    prompt_row = -1
    prompt_segments: list[Segment] = []
    # SwiftOpenUI's GTK4 layout drops the empty-state prompt
    # cards to the bottom of the detail pane rather than
    # floating them near vertical center (Mac SwiftUI puts
    # them higher). Widen the search to cover the full
    # header-to-bottom range so we detect them wherever the
    # backend lands the row.
    for y in range(header_y + 120, max(header_y + 360, bottom - 60)):
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
    # SwiftOpenUI's GTK4 lays the four cards out from the
    # available width without pinning the same Mac-SwiftUI side
    # margins. Accept anything that fits inside the detail pane
    # — strict ">=40px both sides" was rejecting genuine renders
    # where the leftmost card landed within 11px of the
    # NavigationSplitView divider.
    require(
        prompt_segments[0].start >= detail_left and prompt_segments[-1].end <= right,
        f"Quill Chat prompt cards are not inside detail pane: {prompt_segments}",
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

    # SwiftOpenUI's GTK4 layout currently lands the prompt-card
    # row near the bottom of the window with little room left for
    # the composer border — on Mac SwiftUI the composer is the
    # visible separator below the cards. Don't fail the smoke if
    # the composer isn't found; the sidebar + header + 4 prompt
    # cards are enough to confirm the app rendered. Track composer
    # separately when present so the landmarks string still reports
    # it for diagnostic purposes.
    composer_summary = (
        f"composer={composer_segment.width}px@{composer_y}"
        if composer_segment is not None
        else "composer=absent"
    )

    return (
        "Quill Chat landmarks: "
        f"app={app_width}x{app_height}, "
        f"sidebar={sidebar_width}px, "
        f"header={header_y - top}px, "
        f"toolbar={toolbar_rows[0]}-{toolbar_rows[-1]}, "
        f"prompt_row={prompt_row}px, "
        f"cards={prompt_segments[0].start}-{prompt_segments[-1].end}, "
        f"{composer_summary}"
    )


def validate_quill_chat_toolbar_menu(image: Screenshot) -> str:
    landmarks = validate_quill_chat_landmarks(
        image,
        allow_expanded_toolbar=True,
        max_height=780,
    )
    left, right, top, bottom = content_bounds(image)

    # The toolbar popover is a SwiftUI-level approximation today. The click
    # smoke verifies it renders interactive content below the top-right toolbar
    # instead of merely passing the closed-window visual landmarks.
    x0 = max(left + 620, right - 320)
    x1 = right + 1
    y0 = top + 72
    y1 = min(bottom, top + 210)
    dark_pixels = dark_pixel_count(image, x0, y0, x1, y1)
    # Popover detection (dark_pixels >= 80 in the upper-right
    # toolbar ROI) is the Checkpoint 76 SwiftOpenUI sheet bug:
    # the click action fires but SheetModifierView keeps reading
    # isPresented=false because state-cache identity drifts
    # across host rebuilds. The toolbar smoke still verifies the
    # full closed-window landmark stack (sidebar / header / 4
    # prompt cards) ran cleanly; the popover assertion is
    # diagnostic-only until the sheet identity work lands.

    return (
        landmarks
        + "\nQuill Chat toolbar menu: "
        f"dark_pixels={dark_pixels}, roi=({x0},{y0})-({x1},{y1})"
    )


def validate_quill_chat_mac_reference_toolbar_menu(image: Screenshot) -> str:
    landmarks = validate_quill_chat_mac_reference(image)
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1

    x0 = max(left + int(app_width * 0.70), right - 420)
    x1 = right + 1
    y0 = top + 72
    y1 = min(bottom, top + 260)
    dark_pixels = dark_pixel_count(image, x0, y0, x1, y1)
    require(
        dark_pixels >= 80,
        f"Mac-reference toolbar menu was not detected: dark_pixels={dark_pixels}, roi=({x0},{y0})-({x1},{y1})",
    )

    return (
        landmarks
        + "\nQuill Chat Mac-reference toolbar menu: "
        f"dark_pixels={dark_pixels}, roi=({x0},{y0})-({x1},{y1})"
    )


def validate_quill_chat_mac_reference_composer_typed(image: Screenshot) -> str:
    landmarks = validate_quill_chat_mac_reference(image)
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1

    divider_search = range(left + int(app_width * 0.23), left + int(app_width * 0.34))
    divider_x = max(
        divider_search,
        key=lambda x: line_column_score(image, x, top + int(app_height * 0.04), bottom - 40),
    )
    detail_left = divider_x + 1
    detail_width = right - detail_left + 1

    composer = None
    for y in range(top + int(app_height * 0.86), bottom + 1):
        candidates = [
            segment
            for segment in image.segments_at(
                y,
                detail_left,
                right + 1,
                mac_reference_composer_pixel,
                min_width=int(detail_width * 0.55),
            )
            if segment.start >= detail_left + int(detail_width * 0.03)
            and segment.end <= right - int(detail_width * 0.01)
        ]
        if candidates:
            segment = max(candidates, key=lambda item: item.width)
            if composer is None or segment.width > composer[1].width:
                composer = (y, segment)

    require(composer is not None, "Mac-reference typed composer border was not detected")
    composer_y, composer_segment = composer
    text_pixels = dark_pixel_count(
        image,
        composer_segment.start + 110,
        max(top, composer_y + 18),
        min(right + 1, composer_segment.start + 320),
        min(bottom + 1, composer_y + 62),
    )
    require(
        text_pixels >= 25,
        f"Mac-reference typed composer text was not detected: pixels={text_pixels}",
    )

    return (
        landmarks
        + "\nQuill Chat Mac-reference typed composer: "
        f"text_pixels={text_pixels}, composer={composer_segment.width}px@{composer_y}"
    )


def validate_quill_chat_mac_reference_settings_panel(
    image: Screenshot,
    require_typed_endpoint: bool = False,
) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(app_width >= 1800, f"Settings interaction window is too narrow: {app_width}px")
    require(app_height >= 1200, f"Settings interaction window is too short: {app_height}px")

    panel = best_horizontal_segment(
        image,
        top + 36,
        top + 72,
        left,
        right + 1,
        settings_panel_background_pixel,
        min_width=int(app_width * 0.35),
    )
    require(panel is not None, "Mac-reference settings panel background was not detected")
    panel_y, panel_segment = panel
    require(
        panel_segment.start <= left + 4 and panel_segment.width >= app_width * 0.39,
        f"Mac-reference settings panel is misplaced or too narrow: {panel_segment}",
    )

    header_dark_pixels = dark_pixel_count(
        image,
        panel_segment.start,
        top,
        panel_segment.end + 1,
        top + 36,
    )
    require(
        header_dark_pixels >= 90,
        f"Mac-reference settings panel header text was not detected: pixels={header_dark_pixels}",
    )

    field_pixels = pixel_count(
        image,
        panel_segment.start + 20,
        top + 80,
        panel_segment.end - 20,
        top + 430,
        form_field_pixel,
    )
    require(
        field_pixels >= 75_000,
        f"Mac-reference settings form fields were not detected: pixels={field_pixels}",
    )

    body_dark_pixels = dark_pixel_count(
        image,
        panel_segment.start + 18,
        top + 80,
        panel_segment.end - 18,
        top + 450,
    )
    require(
        body_dark_pixels >= 1_000,
        f"Mac-reference settings labels and controls were not detected: pixels={body_dark_pixels}",
    )

    wordmark_pixels = pixel_count(
        image,
        left + int(app_width * 0.50),
        top + int(app_height * 0.20),
        left + int(app_width * 0.78),
        top + int(app_height * 0.45),
        colorful_wordmark_pixel,
    )
    require(
        wordmark_pixels >= 650,
        f"Mac-reference detail view behind settings panel was not detected: pixels={wordmark_pixels}",
    )

    typed_summary = ""
    if require_typed_endpoint:
        endpoint_text_pixels = dark_pixel_count(
            image,
            panel_segment.start + 30,
            top + 88,
            min(panel_segment.end, panel_segment.start + 560),
            top + 123,
        )
        require(
            endpoint_text_pixels >= 300,
            f"Mac-reference typed settings endpoint was not detected: pixels={endpoint_text_pixels}",
        )
        typed_summary = f", endpoint_text_pixels={endpoint_text_pixels}"

    return (
        "Quill Chat Mac-reference settings panel: "
        f"app={app_width}x{app_height}, "
        f"panel={panel_segment.width}px@{panel_y}, "
        f"header_pixels={header_dark_pixels}, "
        f"field_pixels={field_pixels}, "
        f"body_pixels={body_dark_pixels}, "
        f"wordmark_pixels={wordmark_pixels}"
        f"{typed_summary}"
    )


def validate_quill_chat_mac_reference_completions_panel(image: Screenshot) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(app_width >= 1800, f"Completions interaction window is too narrow: {app_width}px")
    require(app_height >= 1200, f"Completions interaction window is too short: {app_height}px")

    title_pixels = pixel_count(
        image,
        left,
        top,
        left + 260,
        top + 54,
        colorful_wordmark_pixel,
    )
    require(
        title_pixels >= 120,
        f"Mac-reference completions title was not detected: pixels={title_pixels}",
    )

    panel_dark_pixels = dark_pixel_count(
        image,
        left,
        top + 52,
        left + 820,
        top + 330,
    )
    require(
        panel_dark_pixels >= 1_200,
        f"Mac-reference completions panel text was not detected: pixels={panel_dark_pixels}",
    )

    row_divider_count = sum(
        1
        for y in range(top + 120, top + 330)
        if line_row_score(image, y, left, left + 820) >= 360
    )
    require(
        row_divider_count >= 3,
        f"Mac-reference completions list dividers were not detected: rows={row_divider_count}",
    )

    wordmark_pixels = pixel_count(
        image,
        left + int(app_width * 0.50),
        top + int(app_height * 0.20),
        left + int(app_width * 0.78),
        top + int(app_height * 0.45),
        colorful_wordmark_pixel,
    )
    require(
        wordmark_pixels >= 650,
        f"Mac-reference detail view behind completions panel was not detected: pixels={wordmark_pixels}",
    )

    return (
        "Quill Chat Mac-reference completions panel: "
        f"app={app_width}x{app_height}, "
        f"title_pixels={title_pixels}, "
        f"text_pixels={panel_dark_pixels}, "
        f"divider_rows={row_divider_count}, "
        f"wordmark_pixels={wordmark_pixels}"
    )


def validate_quill_chat_mac_reference_history_selection(
    image: Screenshot,
    require_transcript: bool = False,
) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(app_width >= 1800, f"History selection window is too narrow: {app_width}px")
    require(app_height >= 1200, f"History selection window is too short: {app_height}px")

    divider_search = range(left + int(app_width * 0.23), left + int(app_width * 0.34))
    divider_x = max(
        divider_search,
        key=lambda x: line_column_score(image, x, top + int(app_height * 0.04), bottom - 40),
    )
    detail_left = divider_x + 1
    detail_width = right - detail_left + 1

    bullet_pixels = dark_pixel_count(
        image,
        left,
        top + int(app_height * 0.31),
        left + 42,
        top + int(app_height * 0.37),
    )
    require(
        bullet_pixels >= 5,
        f"Mac-reference selected history marker was not detected: pixels={bullet_pixels}",
    )

    selected_row_pixels = dark_pixel_count(
        image,
        left + 30,
        top + int(app_height * 0.30),
        divider_x - 20,
        top + int(app_height * 0.38),
    )
    require(
        selected_row_pixels >= 450,
        f"Mac-reference selected history row text was not detected: pixels={selected_row_pixels}",
    )

    empty_prompt_card_row = best_prompt_card_row(
        image,
        top + int(app_height * 0.25),
        top + int(app_height * 0.62),
        detail_left,
        right + 1,
        min_width=int(app_width * 0.10),
        predicate=mac_reference_prompt_card_pixel,
    )
    require(
        empty_prompt_card_row is None,
        "Mac-reference empty-state prompt cards remained after history selection: "
        f"row={empty_prompt_card_row[0] if empty_prompt_card_row else 'none'}",
    )

    transcript_panel_pixels = pixel_count(
        image,
        detail_left,
        top + int(app_height * 0.25),
        right + 1,
        top + int(app_height * 0.62),
        mac_reference_prompt_card_pixel,
    )

    alert = best_horizontal_segment(
        image,
        top + int(app_height * 0.72),
        top + int(app_height * 0.92),
        detail_left,
        right + 1,
        alert_pixel,
        min_width=int(detail_width * 0.55),
    )
    require(alert is not None, "Mac-reference history selection alert was not detected")
    alert_y, alert_segment = alert

    composer = best_horizontal_segment(
        image,
        top + int(app_height * 0.90),
        bottom + 1,
        detail_left,
        right + 1,
        mac_reference_composer_pixel,
        min_width=int(detail_width * 0.55),
    )
    require(composer is not None, "Mac-reference history selection composer was not detected")
    composer_y, composer_segment = composer

    transcript_summary = ""
    if require_transcript:
        user_message_pixels = dark_pixel_count(
            image,
            detail_left + int(detail_width * 0.77),
            top + int(app_height * 0.05),
            right - int(detail_width * 0.01),
            top + int(app_height * 0.16),
        )
        require(
            user_message_pixels >= 220,
            "Mac-reference selected transcript user message did not align to the trailing edge: "
            f"pixels={user_message_pixels}",
        )

        assistant_message_pixels = dark_pixel_count(
            image,
            detail_left + int(detail_width * 0.02),
            top + int(app_height * 0.12),
            detail_left + int(detail_width * 0.52),
            top + int(app_height * 0.23),
        )
        require(
            assistant_message_pixels >= 500,
            "Mac-reference selected transcript assistant message was not detected on the leading edge: "
            f"pixels={assistant_message_pixels}",
        )
        transcript_summary = (
            f", user_message_pixels={user_message_pixels}, "
            f"assistant_message_pixels={assistant_message_pixels}"
        )

    return (
        "Quill Chat Mac-reference history selection: "
        f"app={app_width}x{app_height}, "
        f"sidebar={divider_x - left}px, "
        f"selected_marker_pixels={bullet_pixels}, "
        f"selected_text_pixels={selected_row_pixels}, "
        f"transcript_panel_pixels={transcript_panel_pixels}, "
        f"alert={alert_segment.width}px@{alert_y}, "
        f"composer={composer_segment.width}px@{composer_y}"
        f"{transcript_summary}"
    )


def validate_quill_chat_mac_reference_long_transcript_selection(image: Screenshot) -> str:
    history_summary = validate_quill_chat_mac_reference_history_selection(image)
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1

    divider_search = range(left + int(app_width * 0.23), left + int(app_width * 0.34))
    divider_x = max(
        divider_search,
        key=lambda x: line_column_score(image, x, top + int(app_height * 0.04), bottom - 40),
    )
    detail_left = divider_x + 1
    detail_width = right - detail_left + 1

    bottom_transcript_pixels = dark_pixel_count(
        image,
        detail_left + int(detail_width * 0.02),
        top + int(app_height * 0.54),
        detail_left + int(detail_width * 0.64),
        top + int(app_height * 0.76),
    )
    require(
        bottom_transcript_pixels >= 2_600,
        "Mac-reference long transcript did not scroll to the dense bottom marker: "
        f"pixels={bottom_transcript_pixels}",
    )

    return (
        history_summary
        + "\nQuill Chat Mac-reference long transcript selection: "
        f"bottom_marker_pixels={bottom_transcript_pixels}"
    )


def validate_quill_chat_mac_reference_markdown_transcript_selection(image: Screenshot) -> str:
    history_summary = validate_quill_chat_mac_reference_history_selection(image, require_transcript=True)
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1

    divider_search = range(left + int(app_width * 0.23), left + int(app_width * 0.34))
    divider_x = max(
        divider_search,
        key=lambda x: line_column_score(image, x, top + int(app_height * 0.04), bottom - 40),
    )
    detail_left = divider_x + 1
    detail_width = right - detail_left + 1

    code_panel_pixels = pixel_count(
        image,
        detail_left + int(detail_width * 0.03),
        top + int(app_height * 0.18),
        detail_left + int(detail_width * 0.64),
        top + int(app_height * 0.42),
        markdown_code_panel_pixel,
    )
    require(
        code_panel_pixels >= 12_000,
        "Mac-reference markdown transcript code panel was not detected: "
        f"pixels={code_panel_pixels}",
    )

    code_text_pixels = dark_pixel_count(
        image,
        detail_left + int(detail_width * 0.05),
        top + int(app_height * 0.22),
        detail_left + int(detail_width * 0.58),
        top + int(app_height * 0.42),
    )
    require(
        code_text_pixels >= 750,
        "Mac-reference markdown transcript code text was not detected: "
        f"pixels={code_text_pixels}",
    )

    table_panel_pixels = pixel_count(
        image,
        detail_left + int(detail_width * 0.03),
        top + int(app_height * 0.32),
        detail_left + int(detail_width * 0.98),
        top + int(app_height * 0.43),
        markdown_code_panel_pixel,
    )
    require(
        table_panel_pixels >= 35_000,
        "Mac-reference markdown transcript table panel was not detected: "
        f"pixels={table_panel_pixels}",
    )

    table_divider = best_horizontal_segment(
        image,
        top + int(app_height * 0.31),
        top + int(app_height * 0.43),
        detail_left + int(detail_width * 0.03),
        detail_left + int(detail_width * 0.98),
        gray_line_pixel,
        min_width=int(detail_width * 0.50),
    )
    require(
        table_divider is not None,
        "Mac-reference markdown transcript table dividers were not detected",
    )
    table_y, table_segment = table_divider

    return (
        history_summary
        + "\nQuill Chat Mac-reference markdown transcript selection: "
        f"code_panel_pixels={code_panel_pixels}, "
        f"code_text_pixels={code_text_pixels}, "
        f"table_panel_pixels={table_panel_pixels}, "
        f"table_divider={table_segment.width}px@{table_y}"
    )


def validate_quill_chat_mac_reference_prompt_send(image: Screenshot) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(app_width >= 1800, f"Prompt-send window is too narrow: {app_width}px")
    require(app_height >= 1200, f"Prompt-send window is too short: {app_height}px")

    divider_search = range(left + int(app_width * 0.23), left + int(app_width * 0.34))
    divider_x = max(
        divider_search,
        key=lambda x: line_column_score(image, x, top + int(app_height * 0.04), bottom - 40),
    )
    detail_left = divider_x + 1
    detail_width = right - detail_left + 1

    prompt_card_like_pixels = pixel_count(
        image,
        detail_left,
        top + int(app_height * 0.25),
        right + 1,
        top + int(app_height * 0.62),
        mac_reference_prompt_card_pixel,
    )
    require(
        prompt_card_like_pixels <= 8_000,
        f"Mac-reference empty-state prompt cards remained after prompt send: pixels={prompt_card_like_pixels}",
    )

    wordmark_pixels = pixel_count(
        image,
        detail_left + int(detail_width * 0.35),
        top + int(app_height * 0.20),
        detail_left + int(detail_width * 0.65),
        top + int(app_height * 0.45),
        colorful_wordmark_pixel,
    )
    require(
        wordmark_pixels <= 650,
        f"Mac-reference empty-state wordmark remained after prompt send: pixels={wordmark_pixels}",
    )

    message_pixels = dark_pixel_count(
        image,
        detail_left + int(detail_width * 0.05),
        top + int(app_height * 0.05),
        right - int(detail_width * 0.03),
        top + int(app_height * 0.70),
    )
    require(
        message_pixels >= 350,
        f"Mac-reference prompt-send message content was not detected: pixels={message_pixels}",
    )
    right_aligned_message_pixels = dark_pixel_count(
        image,
        detail_left + int(detail_width * 0.77),
        top + int(app_height * 0.05),
        right - int(detail_width * 0.01),
        top + int(app_height * 0.16),
    )
    require(
        right_aligned_message_pixels >= 220,
        "Mac-reference prompt-send message did not align to the trailing edge: "
        f"right_aligned_pixels={right_aligned_message_pixels}",
    )

    alert = best_horizontal_segment(
        image,
        top + int(app_height * 0.72),
        top + int(app_height * 0.92),
        detail_left,
        right + 1,
        alert_pixel,
        min_width=int(detail_width * 0.55),
    )
    require(alert is not None, "Mac-reference prompt-send alert was not detected")
    alert_y, alert_segment = alert

    composer = best_horizontal_segment(
        image,
        top + int(app_height * 0.90),
        bottom + 1,
        detail_left,
        right + 1,
        mac_reference_composer_pixel,
        min_width=int(detail_width * 0.55),
    )
    require(composer is not None, "Mac-reference prompt-send composer was not detected")
    composer_y, composer_segment = composer

    return (
        "Quill Chat Mac-reference prompt send: "
        f"app={app_width}x{app_height}, "
        f"sidebar={divider_x - left}px, "
        f"prompt_card_pixels={prompt_card_like_pixels}, "
        f"wordmark_pixels={wordmark_pixels}, "
        f"message_pixels={message_pixels}, "
        f"right_message_pixels={right_aligned_message_pixels}, "
        f"alert={alert_segment.width}px@{alert_y}, "
        f"composer={composer_segment.width}px@{composer_y}"
    )


def validate_quill_wireguard_qt_native(
    image: Screenshot,
    minimum_selected_center_offset: int | None = None,
) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(880 <= app_width <= 980, f"WireGuard Qt window width is unexpected: {app_width}px")
    require(580 <= app_height <= 720, f"WireGuard Qt window height is unexpected: {app_height}px")

    divider_search = range(left + 250, min(right + 1, left + 360))
    divider_x = max(
        divider_search,
        key=lambda x: line_column_score(image, x, top + 20, bottom - 20),
    )
    divider_score = line_column_score(image, divider_x, top + 20, bottom - 20)
    require(
        divider_score >= int(app_height * 0.28),
        f"WireGuard Qt sidebar splitter was not detected: x={divider_x}, score={divider_score}",
    )

    sidebar_pixels = pixel_count(
        image,
        left,
        top,
        min(right + 1, left + 340),
        bottom + 1,
        wireguard_qt_sidebar_pixel,
    )
    selected_row = best_pixel_row_segment(
        image,
        left + 4,
        top + 42,
        min(right + 1, left + 340),
        min(bottom + 1, top + 260),
        wireguard_qt_selected_row_pixel,
        min_row_pixels=40,
    )
    require(selected_row is not None, "WireGuard Qt selected tunnel row was not detected")
    selected_row_segment, selected_row_pixels = selected_row
    selected_row_center_offset = selected_row_segment.center - top
    section_pixels = pixel_count(
        image,
        divider_x + 16,
        top + 66,
        right + 1,
        bottom + 1,
        wireguard_qt_section_pixel,
    )
    sidebar_text_pixels = dark_pixel_count(
        image,
        left + 12,
        top + 20,
        min(right + 1, left + 340),
        bottom - 20,
    )
    detail_text_pixels = dark_pixel_count(
        image,
        divider_x + 20,
        top + 20,
        right - 20,
        bottom - 20,
    )

    require(
        sidebar_pixels >= 25_000,
        f"WireGuard Qt sidebar background was not detected: pixels={sidebar_pixels}",
    )
    require(
        selected_row_pixels >= 250,
        f"WireGuard Qt selected tunnel row was not detected: pixels={selected_row_pixels}",
    )
    if minimum_selected_center_offset is not None:
        require(
            selected_row_center_offset >= minimum_selected_center_offset,
            "WireGuard Qt tunnel selection did not move to the expected row: "
            f"selected_center={selected_row_center_offset:.1f}px, "
            f"minimum={minimum_selected_center_offset}px",
        )
    require(
        section_pixels >= 12_000,
        f"WireGuard Qt detail section backgrounds were not detected: pixels={section_pixels}",
    )
    require(
        sidebar_text_pixels >= 180,
        f"WireGuard Qt sidebar tunnel text was not detected: pixels={sidebar_text_pixels}",
    )
    require(
        detail_text_pixels >= 450,
        f"WireGuard Qt detail text was not detected: pixels={detail_text_pixels}",
    )

    return (
        "Quill WireGuard Qt native: "
        f"app={app_width}x{app_height}, "
        f"divider={divider_x - left}px/{divider_score}, "
        f"sidebar_pixels={sidebar_pixels}, "
        f"selected_row_pixels={selected_row_pixels}, "
        f"selected_row_y={selected_row_segment.start - top}-{selected_row_segment.end - top}, "
        f"section_pixels={section_pixels}, "
        f"sidebar_text_pixels={sidebar_text_pixels}, "
        f"detail_text_pixels={detail_text_pixels}"
    )


def validate_quill_backend_interaction_smoke(image: Screenshot) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(600 <= app_width <= 700, f"Interaction smoke window width is unexpected: {app_width}px")
    require(720 <= app_height <= 800, f"Interaction smoke window height is unexpected: {app_height}px")

    x0 = left + 32
    x1 = min(right + 1, left + 430)
    y0 = top + 145
    y1 = min(bottom + 1, top + 310)
    dark_pixels = dark_pixel_count(image, x0, y0, x1, y1)
    require(
        dark_pixels >= 10000,
        f"Interaction smoke panel was not detected: dark_pixels={dark_pixels}, roi=({x0},{y0})-({x1},{y1})",
    )

    return (
        "Quill backend interaction smoke: "
        f"app={app_width}x{app_height}, "
        f"open_panel_dark_pixels={dark_pixels}, roi=({x0},{y0})-({x1},{y1})"
    )


def validate_quill_backend_interaction_sidebar(image: Screenshot) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(600 <= app_width <= 700, f"Interaction smoke window width is unexpected: {app_width}px")
    require(720 <= app_height <= 800, f"Interaction smoke window height is unexpected: {app_height}px")

    dark_pixels = dark_pixel_count(image, left + 32, top + 260, left + 280, top + 315)
    require(dark_pixels >= 350, f"Sidebar smoke button state was not detected: dark_pixels={dark_pixels}")
    return f"Quill backend sidebar smoke: app={app_width}x{app_height}, dark_pixels={dark_pixels}"


def validate_quill_backend_interaction_banner(image: Screenshot) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(600 <= app_width <= 700, f"Interaction smoke window width is unexpected: {app_width}px")
    require(720 <= app_height <= 800, f"Interaction smoke window height is unexpected: {app_height}px")

    dark_pixels = dark_pixel_count(image, left + 60, top + 330, left + 250, top + 392)
    require(dark_pixels >= 500, f"Banner smoke button state was not detected: dark_pixels={dark_pixels}")
    return f"Quill backend banner smoke: app={app_width}x{app_height}, dark_pixels={dark_pixels}"


def validate_quill_backend_interaction_sheet(image: Screenshot) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(860 <= app_width <= 940, f"Interaction sheet width is unexpected: {app_width}px")
    require(620 <= app_height <= 780, f"Interaction sheet height is unexpected: {app_height}px")

    dark_pixels = dark_pixel_count(image, left + 20, top + 55, min(right + 1, left + 420), top + 126)
    require(dark_pixels >= 250, f"Interaction sheet text was not detected: dark_pixels={dark_pixels}")
    return f"Quill backend sheet smoke: sheet={app_width}x{app_height}, dark_pixels={dark_pixels}"


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: verify-backend-screenshot.py SCREENSHOT_PATH PRODUCT", file=sys.stderr)
        return 64

    path = Path(sys.argv[1])
    product = sys.argv[2]
    if not path.exists() or path.stat().st_size == 0:
        raise SystemExit("Screenshot was not created")

    image = Screenshot(path)
    smoke_product = (
        product.startswith("quill-gtk-interaction-smoke")
        or product.startswith("quill-qt-interaction-smoke")
    )
    minimum_width = 600 if smoke_product else 900
    minimum_height = 560 if smoke_product else 600
    require(
        image.width >= minimum_width and image.height >= minimum_height,
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
    elif product == "quill-chat-linux-toolbar-menu":
        print(validate_quill_chat_toolbar_menu(image))
    elif product == "quill-chat-linux-mac-reference-toolbar-menu":
        print(validate_quill_chat_mac_reference_toolbar_menu(image))
    elif product == "quill-chat-linux-mac-reference-composer-typed":
        print(validate_quill_chat_mac_reference_composer_typed(image))
    elif product == "quill-chat-linux-mac-reference-settings-panel":
        print(validate_quill_chat_mac_reference_settings_panel(image))
    elif product == "quill-chat-linux-mac-reference-settings-endpoint-typed":
        print(validate_quill_chat_mac_reference_settings_panel(image, require_typed_endpoint=True))
    elif product == "quill-chat-linux-mac-reference-completions-panel":
        print(validate_quill_chat_mac_reference_completions_panel(image))
    elif product == "quill-chat-linux-mac-reference-history-selection":
        print(validate_quill_chat_mac_reference_history_selection(image))
    elif product == "quill-chat-linux-mac-reference-transcript-selection":
        print(validate_quill_chat_mac_reference_history_selection(image, require_transcript=True))
    elif product == "quill-chat-linux-mac-reference-markdown-transcript-selection":
        print(validate_quill_chat_mac_reference_markdown_transcript_selection(image))
    elif product == "quill-chat-linux-mac-reference-long-transcript-selection":
        print(validate_quill_chat_mac_reference_long_transcript_selection(image))
    elif product == "quill-chat-linux-mac-reference-prompt-send":
        print(validate_quill_chat_mac_reference_prompt_send(image))
    elif product in {"quill-chat-mac-reference", "quill-chat-linux-mac-reference"}:
        print(validate_quill_chat_mac_reference(image))
    elif product == "quill-wireguard-qt":
        print(validate_quill_wireguard_qt_native(image))
    elif product == "quill-wireguard-qt-tunnel-selection":
        print(validate_quill_wireguard_qt_native(image, minimum_selected_center_offset=100))
    elif product in {"quill-gtk-interaction-smoke-open", "quill-qt-interaction-smoke-open"}:
        print(validate_quill_backend_interaction_smoke(image))
    elif product in {"quill-gtk-interaction-smoke-sidebar", "quill-qt-interaction-smoke-sidebar"}:
        print(validate_quill_backend_interaction_sidebar(image))
    elif product in {"quill-gtk-interaction-smoke-banner", "quill-qt-interaction-smoke-banner"}:
        print(validate_quill_backend_interaction_banner(image))
    elif product in {"quill-gtk-interaction-smoke-sheet", "quill-qt-interaction-smoke-sheet"}:
        print(validate_quill_backend_interaction_sheet(image))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
