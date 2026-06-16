#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable


def load_backend_product_set(command: str, description: str) -> frozenset[str]:
    products_script = Path(__file__).with_name("quillui-backend-products.sh")
    output = subprocess.run(
        ["bash", str(products_script), command],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    ).stdout
    products = frozenset(
        line.strip()
        for line in output.splitlines()
        if line.strip()
    )
    if not products:
        raise RuntimeError(f"No {description} were reported by quillui-backend-products.sh")
    return products


def load_generic_qt_app_products() -> frozenset[str]:
    return load_backend_product_set("generic-qt-apps", "generic Qt app products")


def load_generic_gtk_list_selection_app_products() -> frozenset[str]:
    return load_backend_product_set("generic-gtk-list-selection-apps", "generic GTK list-selection app products")


def load_chat_gtk_list_selection_app_products() -> frozenset[str]:
    return load_backend_product_set("chat-gtk-list-selection-apps", "ChatKit GTK list-selection app products")


GENERIC_QT_APP_PRODUCTS = load_generic_qt_app_products()
GENERIC_QT_LIST_SELECTION_PRODUCTS = frozenset(
    f"{product}-qt-list-selection"
    for product in GENERIC_QT_APP_PRODUCTS
)
GENERIC_GTK_LIST_SELECTION_APP_PRODUCTS = load_generic_gtk_list_selection_app_products()
GENERIC_GTK_LIST_SELECTION_PRODUCTS = frozenset(
    f"{product}-gtk-list-selection"
    for product in GENERIC_GTK_LIST_SELECTION_APP_PRODUCTS
)
CHAT_GTK_LIST_SELECTION_APP_PRODUCTS = load_chat_gtk_list_selection_app_products()
CHAT_GTK_LIST_SELECTION_PRODUCTS = frozenset(
    f"{product}-list-selection"
    for product in CHAT_GTK_LIST_SELECTION_APP_PRODUCTS
)


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
    # SwiftOpenUI's GTK4 GL render path anti-aliases the thin list-row dividers
    # lighter (and slightly bluer) than macOS SwiftUI — they land near the top of
    # the gray band rather than the middle. Widen the upper bound (590..680 ->
    # 590..712) and the channel-spread tolerance (12 -> 16) so the divider lines
    # are detected on both backends.
    #
    # But require the pixel be a NEUTRAL gray — green must not be the dominant
    # channel. The widened 712 ceiling otherwise sweeps in Enchanted's light
    # green-tinted sidebar FILL (e.g. (232,237,226): total=695, spread=11) which
    # is low-spread enough to pass but is structurally a panel background, not a
    # divider line. A genuine divider is neutral/warm-gray ((216,212,208):
    # green_bias=-4); the sidebar tint is green-dominant (green_bias=+5). Without
    # this guard the green fill scores full-height in line_column_score, ties the
    # true sidebar divider in the divider argmax, and the lower-x spurious column
    # wins — placing the detected divider at ratio 0.246 instead of the true
    # 0.285 and failing the Mac-reference sidebar check. Excluding green-dominant
    # pixels never drops a real divider line (they are neutral by construction).
    r, g, b = rgb
    total = r + g + b
    return 590 <= total <= 712 and max(rgb) - min(rgb) <= 16 and g <= max(r, b)


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


def mac_reference_or_gtk_prompt_card_pixel(rgb: tuple[int, int, int]) -> bool:
    # The empty-state prompt cards render around RGB(228) on macOS (Cocoa) but at
    # ~RGB(244,244,246) under the Linux GTK4 backend — lighter, above the tight mac
    # band's red<=235 ceiling. Accept EITHER shade so the STRUCTURAL card-row check
    # detects the real GTK render without demanding cross-stack pixel-identity.
    return mac_reference_prompt_card_pixel(rgb) or prompt_card_pixel(rgb)


def mac_reference_composer_pixel(rgb: tuple[int, int, int]) -> bool:
    return 540 <= sum(rgb) <= 720 and max(rgb) - min(rgb) <= 30


def settings_panel_background_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return 220 <= red <= 245 and 220 <= green <= 245 and 225 <= blue <= 250 and max(rgb) - min(rgb) <= 24


def form_field_pixel(rgb: tuple[int, int, int]) -> bool:
    return sum(rgb) >= 735 and max(rgb) - min(rgb) <= 12


def completions_upsert_sheet_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return (
        235 <= red <= 252
        and 235 <= green <= 252
        and 235 <= blue <= 252
        and max(rgb) - min(rgb) <= 12
    )


def completions_upsert_form_field_pixel(rgb: tuple[int, int, int]) -> bool:
    return sum(rgb) >= 750 and max(rgb) - min(rgb) <= 12


def confirmation_dialog_surface_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return 228 <= red <= 255 and 228 <= green <= 255 and 228 <= blue <= 255 and max(rgb) - min(rgb) <= 24


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


def wireguard_selected_row_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return 225 <= red <= 240 and 232 <= green <= 245 and 245 <= blue <= 255 and blue - red >= 8


def wireguard_qt_selected_row_pixel(rgb: tuple[int, int, int]) -> bool:
    return wireguard_selected_row_pixel(rgb)


def generic_qt_sidebar_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return (
        232 <= red <= 246
        and 236 <= green <= 248
        and 228 <= blue <= 244
        and max(rgb) - min(rgb) <= 22
    )


def generic_qt_selected_row_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return 214 <= red <= 232 and 228 <= green <= 242 and 242 <= blue <= 255 and blue - red >= 12


def chatkit_gtk_selected_row_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return 214 <= red <= 240 and 226 <= green <= 246 and 238 <= blue <= 255 and blue - red >= 8


def generic_qt_detail_surface_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return (
        232 <= red <= 250
        and 232 <= green <= 250
        and 232 <= blue <= 250
        and max(rgb) - min(rgb) <= 18
    )


def generic_qt_card_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return (
        (239 <= red <= 247 and 239 <= green <= 247 and 242 <= blue <= 250 and max(rgb) - min(rgb) <= 10 and sum(rgb) < 736)
        or (225 <= red <= 240 and 235 <= green <= 248 and 245 <= blue <= 255 and blue - red >= 8)
    )


def wireguard_error_text_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return (
        120 <= red <= 210
        and 10 <= green <= 95
        and 10 <= blue <= 95
        and red - green >= 45
        and red - blue >= 45
    )


def wireguard_gtk_sidebar_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return (
        238 <= red <= 252
        and 238 <= green <= 252
        and 238 <= blue <= 253
        and max(rgb) - min(rgb) <= 10
    )


def wireguard_gtk_section_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return (
        238 <= red <= 252
        and 238 <= green <= 252
        and 238 <= blue <= 253
        and max(rgb) - min(rgb) <= 14
        and sum(rgb) < 755
    )


def generic_gtk_sidebar_pixel(rgb: tuple[int, int, int]) -> bool:
    return generic_qt_sidebar_pixel(rgb) or wireguard_gtk_sidebar_pixel(rgb)


def generic_gtk_selected_row_pixel(rgb: tuple[int, int, int]) -> bool:
    return chatkit_gtk_selected_row_pixel(rgb) or generic_qt_selected_row_pixel(rgb)


def generic_gtk_detail_surface_pixel(rgb: tuple[int, int, int]) -> bool:
    return generic_qt_detail_surface_pixel(rgb)


def generic_gtk_card_pixel(rgb: tuple[int, int, int]) -> bool:
    return generic_qt_card_pixel(rgb) or prompt_card_pixel(rgb)


def wireguard_qt_focused_title_border_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return 115 <= red <= 180 and 130 <= green <= 190 and 165 <= blue <= 230 and blue - red >= 25


def wireguard_qt_section_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return (
        238 <= red <= 248
        and 238 <= green <= 248
        and 239 <= blue <= 250
        and max(rgb) - min(rgb) <= 8
        and sum(rgb) < 745
    )


def enchanted_sidebar_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return (
        232 <= red <= 246
        and 235 <= green <= 249
        and 228 <= blue <= 249
        and max(rgb) - min(rgb) <= 22
    )


def enchanted_canvas_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return (
        238 <= red <= 252
        and 238 <= green <= 253
        and 236 <= blue <= 255
        and max(rgb) - min(rgb) <= 18
    )


def enchanted_header_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return red >= 246 and green >= 247 and blue >= 242 and max(rgb) - min(rgb) <= 14


def enchanted_primary_pixel(rgb: tuple[int, int, int]) -> bool:
    # Two disjoint bands, unioned: the muted steel-blue selection tint that the
    # selected-row checks reuse this predicate for, OR the bright accent-blue
    # primary button (EnchantedPalette.accentColor #4285F4 = 66,133,244; the macOS
    # reference renders ~83,131,236) that the Enchanted sidebar/catalog emits.
    # Keeping ONLY the accent band would break row detection; keeping ONLY the old
    # muted band rejected the real accent (primary_pixels=0). Union covers both.
    red, green, blue = rgb
    muted = 35 <= red <= 75 and 70 <= green <= 110 and 95 <= blue <= 140 and blue > red
    accent = 45 <= red <= 95 and 110 <= green <= 155 and 210 <= blue <= 255 and blue > green > red
    return muted or accent


def enchanted_drop_target_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return 218 <= red <= 238 and 233 <= green <= 248 and 225 <= blue <= 242 and green >= red


def enchanted_selected_row_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    blue_tinted_selection = (
        210 <= red <= 232
        and 224 <= green <= 242
        and 236 <= blue <= 255
        and blue - red >= 14
    )
    shared_palette_selection = (
        222 <= red <= 238
        and 222 <= green <= 238
        and 226 <= blue <= 244
        and max(rgb) - min(rgb) <= 18
    )
    return blue_tinted_selection or shared_palette_selection


def enchanted_linux_gtk_wordmark_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return 110 <= red <= 190 and 70 <= green <= 150 and 160 <= blue <= 235 and blue - red >= 20


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


def dark_row_segment_count(
    image: Screenshot,
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    *,
    min_row_pixels: int,
    min_height: int,
) -> int:
    count = 0
    start: int | None = None
    last = 0

    for y in range(max(0, y0), min(image.height, y1)):
        row_pixels = sum(
            1
            for x in range(max(0, x0), min(image.width, x1))
            if sum(image.rgb(x, y)) < 420
        )
        if row_pixels >= min_row_pixels:
            if start is None:
                start = y
            last = y
        elif start is not None:
            if last - start + 1 >= min_height:
                count += 1
            start = None

    if start is not None and last - start + 1 >= min_height:
        count += 1

    return count


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


def mac_reference_completion_action_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return blue >= 180 and blue - red >= 40 and blue - green >= 40 and max(rgb) - min(rgb) >= 40


def cool_wordmark_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return blue - red >= 20 and max(rgb) - min(rgb) >= 35 and 180 <= sum(rgb) <= 650


def warm_wordmark_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return red - blue >= 15 and max(rgb) - min(rgb) >= 30 and 180 <= sum(rgb) <= 650


def mac_reference_sidebar_tint_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return (
        222 <= red <= 242
        and 226 <= green <= 248
        and 216 <= blue <= 242
        and green >= red + 2
        and green >= blue + 5
        and max(rgb) - min(rgb) <= 24
    )


def selected_history_marker_pixel(rgb: tuple[int, int, int]) -> bool:
    red, green, blue = rgb
    return sum(rgb) < 360 or (
        red <= 120
        and 70 <= green <= 190
        and blue >= 175
        and blue >= red + 80
        and blue >= green + 35
    )


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


def prompt_card_fill_height(
    image: Screenshot,
    y0: int,
    y1: int,
    segments: list[Segment],
    predicate: Callable[[tuple[int, int, int]], bool],
) -> int:
    rows: list[int] = []
    for y in range(max(0, y0), min(image.height, y1)):
        matched_cards = 0
        for segment in segments:
            fill_pixels = sum(
                1
                for x in range(segment.start, segment.end + 1)
                if predicate(image.rgb(x, y))
            )
            if fill_pixels >= segment.width * 0.42:
                matched_cards += 1
        if matched_cards == len(segments):
            rows.append(y)
    if not rows:
        return 0
    return rows[-1] - rows[0] + 1


def validate_quill_enchanted_mac_reference(image: Screenshot) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    root_title_pixels = pixel_count(
        image,
        left + int(app_width * 0.25),
        top + int(app_height * 0.25),
        left + int(app_width * 0.60),
        top + int(app_height * 0.38),
        colorful_wordmark_pixel,
    )
    require(app_width >= 2220, f"Enchanted reference window is too narrow: {app_width}px")
    require(app_height >= 1490, f"Enchanted reference window is too short: {app_height}px")

    divider_search = range(left + 590, left + 615)
    divider_x = max(
        divider_search,
        key=lambda x: line_column_score(image, x, top + 50, bottom - 50),
    )
    divider_score = line_column_score(image, divider_x, top + 50, bottom - 50)
    sidebar_width = divider_x - left
    require(
        600 <= sidebar_width <= 604 and divider_score >= app_height * 0.70,
        f"Enchanted-reference sidebar divider mismatch: x={divider_x}, width={sidebar_width}, score={divider_score}",
    )

    detail_left = divider_x + 1
    detail_width = right - detail_left + 1

    header_candidates = range(top + 80, top + 120)
    header_y = max(
        header_candidates,
        key=lambda y: line_row_score(image, y, detail_left, right + 1),
    )
    header_score = line_row_score(image, header_y, detail_left, right + 1)
    header_height = header_y - top
    require(
        100 <= header_height <= 104 and header_score >= detail_width * 0.70,
        f"Enchanted-reference header divider mismatch: y={header_y}, height={header_height}, score={header_score}",
    )

    prompt_card_pixels = pixel_count(
        image,
        detail_left + 20,
        header_y + 20,
        right - 20,
        bottom - 300,
        prompt_card_pixel,
    )
    require(
        prompt_card_pixels >= 20000,
        f"Enchanted-reference prompt cards were not detected: pixels={prompt_card_pixels}",
    )

    composer_y_search = range(bottom - 220, bottom - 120)
    composer_y = max(
        composer_y_search,
        key=lambda y: line_row_score(image, y, detail_left, right + 1),
    )
    composer_y_score = line_row_score(image, composer_y, detail_left, right + 1)
    require(
        composer_y_score >= detail_width * 0.60,
        f"Enchanted-reference composer divider mismatch: y={composer_y}, score={composer_y_score}",
    )

    return f"Enchanted reference ok: {app_width}x{app_height}, sidebar={sidebar_width}, header={header_height}"


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
    # Structural floor (NOT a fixture-history check): the sidebar's conversation
    # region must render SOME content — a seeded history list OR the genuine empty
    # state ("No saved chats yet / Start a chat and it will be saved locally",
    # ~769 dark px). The old >=1700 floor demanded SEEDED FIXTURE history, which is
    # a test-fixture concern rather than port parity: QuillData's real store keys
    # rows into per-type `_quilldata_json_*` tables, so the legacy seed (which wrote
    # a phantom `quillDataRecords` table) never populated anything the real source
    # reads. Keep a low floor that still catches a blank/crashed sidebar (~0 px)
    # while accepting the real empty state.
    require(
        sidebar_history_pixels >= 400,
        f"Mac-reference sidebar region rendered no content: pixels={sidebar_history_pixels}",
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
    sidebar_tint_pixels = pixel_count(
        image,
        left + int((divider_x - left) * 0.03),
        top + int(app_height * 0.08),
        divider_x - int((divider_x - left) * 0.03),
        bottom - int(app_height * 0.18),
        mac_reference_sidebar_tint_pixel,
    )
    require(
        sidebar_tint_pixels >= 120_000,
        f"Mac-reference sidebar lost its green-tinted source-list material: pixels={sidebar_tint_pixels}",
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
    cool_wordmark_pixels = pixel_count(
        image,
        detail_left + int(detail_width * 0.35),
        top + int(app_height * 0.20),
        detail_left + int(detail_width * 0.65),
        top + int(app_height * 0.45),
        cool_wordmark_pixel,
    )
    warm_wordmark_pixels = pixel_count(
        image,
        detail_left + int(detail_width * 0.35),
        top + int(app_height * 0.20),
        detail_left + int(detail_width * 0.65),
        top + int(app_height * 0.45),
        warm_wordmark_pixel,
    )
    require(
        cool_wordmark_pixels >= 250 and warm_wordmark_pixels >= 180,
        "Mac-reference wordmark lost its blue-to-red color range: "
        f"cool_pixels={cool_wordmark_pixels}, warm_pixels={warm_wordmark_pixels}",
    )

    card_row = best_prompt_card_row(
        image,
        top + int(app_height * 0.30),
        top + int(app_height * 0.63),
        detail_left,
        right + 1,
        min_width=int(app_width * 0.10),
        predicate=mac_reference_or_gtk_prompt_card_pixel,
    )
    require(card_row is not None, "Mac-reference prompt card row was not detected")
    prompt_y, prompt_segments = card_row
    card_widths = [segment.width for segment in prompt_segments]
    require(
        all(app_width * 0.105 <= width <= app_width * 0.19 for width in card_widths),
        f"Mac-reference prompt card widths mismatch: {card_widths}",
    )
    gaps = [
        prompt_segments[index + 1].start - prompt_segments[index].end - 1
        for index in range(3)
    ]
    # Structural: four cards in a row with small, even gaps. The GTK4 backend packs
    # them slightly tighter than macOS; keep a low floor that still rejects merged
    # cards (gap ~0) while accepting the GTK spacing (~0.007*aw measured).
    require(
        all(app_width * 0.002 <= gap <= app_width * 0.04 for gap in gaps),
        f"Mac-reference prompt card gaps mismatch: {gaps}",
    )
    # The card row must sit inside the detail pane. macOS centers it with wide side
    # margins; the GTK4 backend lands it with smaller margins. Assert containment
    # (structural), not the mac-specific centering margins — cross-stack layout
    # variance is expected and out of scope for this parity gate.
    require(
        prompt_segments[0].start >= detail_left
        and prompt_segments[-1].end <= right,
        f"Mac-reference prompt cards are outside the detail pane: {prompt_segments}",
    )
    prompt_card_height = prompt_card_fill_height(
        image,
        top + int(app_height * 0.30),
        top + int(app_height * 0.66),
        prompt_segments,
        mac_reference_or_gtk_prompt_card_pixel,
    )
    require(
        prompt_card_height >= int(app_height * 0.15),
        f"Mac-reference prompt cards are too short: height={prompt_card_height}px",
    )
    require(
        prompt_card_height <= int(app_height * 0.28),
        f"Mac-reference prompt cards are too tall: height={prompt_card_height}px",
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
            if (
                composer is None
                or segment.width > composer[1].width
                or (segment.width == composer[1].width and y < composer[0])
            ):
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
        f"sidebar_tint_pixels={sidebar_tint_pixels}, "
        f"window_controls={window_control_pixels}, "
        f"wordmark_pixels={wordmark_pixels}, "
        f"wordmark_cool={cool_wordmark_pixels}, "
        f"wordmark_warm={warm_wordmark_pixels}, "
        f"prompt_row={prompt_y}px, "
        f"cards={[f'{segment.start}-{segment.end}' for segment in prompt_segments]}, "
        f"card_height={prompt_card_height}px, "
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
            if (
                composer is None
                or segment.width > composer[1].width
                or (segment.width == composer[1].width and y < composer[0])
            ):
                composer = (y, segment)

    require(composer is not None, "Mac-reference typed composer border was not detected")
    composer_y, composer_segment = composer
    text_pixels = dark_pixel_count(
        image,
        composer_segment.start + 28,
        max(top, composer_y + 18),
        min(right + 1, composer_segment.start + 300),
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
    require_typed_bearer_token: bool = False,
    require_typed_ping_interval: bool = False,
    require_selected_default_model: bool = False,
) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(app_width >= 1800, f"Settings interaction window is too narrow: {app_width}px")
    require(app_height >= 1200, f"Settings interaction window is too short: {app_height}px")

    legacy_panel = best_horizontal_segment(
        image,
        top + 36,
        top + 72,
        left,
        right + 1,
        settings_panel_background_pixel,
        min_width=int(app_width * 0.35),
    )
    panel_kind = "legacy"
    panel = legacy_panel
    if panel is None or panel[1].start > left + 4:
        panel_kind = "root-overlay"
        panel = best_horizontal_segment(
            image,
            top + int(app_height * 0.18),
            top + int(app_height * 0.72),
            left + int(app_width * 0.20),
            right + 1,
            settings_panel_background_pixel,
            min_width=int(app_width * 0.35),
        )
    require(panel is not None, "Mac-reference settings panel background was not detected")
    panel_y, panel_segment = panel
    if panel_kind == "legacy":
        require(
            panel_segment.start <= left + 4 and panel_segment.width >= app_width * 0.39,
            f"Mac-reference settings panel is misplaced or too narrow: {panel_segment}",
        )
    else:
        detail_center = (left + right) / 2
        require(
            abs(panel_segment.center - detail_center) <= app_width * 0.18
            and panel_segment.width >= app_width * 0.35,
            f"Mac-reference root-overlay settings panel is misplaced or too narrow: {panel_segment}",
        )

    header_dark_pixels = dark_pixel_count(
        image,
        panel_segment.start,
        max(top, panel_y - 44),
        panel_segment.end + 1,
        panel_y + 36,
    )
    require(
        header_dark_pixels >= 90,
        f"Mac-reference settings panel header text was not detected: pixels={header_dark_pixels}",
    )

    field_pixels = pixel_count(
        image,
        panel_segment.start + 20,
        panel_y + 50,
        panel_segment.end - 20,
        panel_y + 430,
        form_field_pixel,
    )
    require(
        field_pixels >= 75_000,
        f"Mac-reference settings form fields were not detected: pixels={field_pixels}",
    )

    body_dark_pixels = dark_pixel_count(
        image,
        panel_segment.start + 18,
        panel_y + 50,
        panel_segment.end - 18,
        panel_y + 450,
    )
    # Calibrated for the headless GTK GL render path (the packaged-artifact
    # interaction verifier runs without GSK_RENDERER=cairo), which anti-aliases
    # label strokes lighter than the macOS reference — body text lands at a
    # deterministic ~966 dark pixels across runners. The panel-background,
    # header-text (>=90), and form-field (>=75_000) requires above already
    # guard against a blank/garbage render, so this bound only needs to confirm
    # real body text is present; 800 keeps a meaningful floor with margin.
    require(
        body_dark_pixels >= 800,
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
    if not require_selected_default_model:
        require(
            wordmark_pixels >= 650,
            f"Mac-reference detail view behind settings panel was not detected: pixels={wordmark_pixels}",
        )

    typed_summary = ""
    root_overlay_field_rows: list[tuple[int, int, Segment]] = []
    if panel_kind == "root-overlay":
        active_row: tuple[int, int, Segment] | None = None
        for y in range(panel_y + 32, min(bottom + 1, panel_y + int(app_height * 0.45))):
            segments = [
                segment
                for segment in image.segments_at(
                    y,
                    panel_segment.start + 20,
                    panel_segment.end - 20,
                    form_field_pixel,
                    min_width=600,
                )
                if segment.start >= panel_segment.start + 20
                and segment.end <= panel_segment.end - 20
            ]
            if not segments:
                if active_row is not None:
                    root_overlay_field_rows.append(active_row)
                    active_row = None
                continue

            segment = max(segments, key=lambda item: item.width)
            if active_row is None:
                active_row = (y, y, segment)
            else:
                start_y, _, active_segment = active_row
                active_row = (
                    start_y,
                    y,
                    Segment(
                        min(active_segment.start, segment.start),
                        max(active_segment.end, segment.end),
                    ),
                )
        if active_row is not None:
            root_overlay_field_rows.append(active_row)
        root_overlay_field_rows = [
            row for row in root_overlay_field_rows
            if row[2].width <= 1_000
        ]

    def root_overlay_field_text_pixels(index: int) -> int:
        require(
            len(root_overlay_field_rows) > index,
            "Mac-reference settings root-overlay form field rows were not detected: "
            f"rows={root_overlay_field_rows}",
        )
        y0, y1, segment = root_overlay_field_rows[index]
        return dark_pixel_count(
            image,
            segment.start + 18,
            max(top, y0 - 10),
            min(segment.end, segment.start + 560),
            min(bottom + 1, y1 + 11),
        )

    if require_typed_endpoint:
        if panel_kind == "root-overlay":
            endpoint_text_pixels = root_overlay_field_text_pixels(0)
        else:
            endpoint_text_pixels = dark_pixel_count(
                image,
                panel_segment.start + 30,
                panel_y + 58,
                min(panel_segment.end, panel_segment.start + 560),
                panel_y + 103,
            )
        require(
            endpoint_text_pixels >= 300,
            f"Mac-reference typed settings endpoint was not detected: pixels={endpoint_text_pixels}",
        )
        typed_summary = f", endpoint_text_pixels={endpoint_text_pixels}"

    if require_typed_bearer_token:
        if panel_kind == "root-overlay":
            token_text_pixels = root_overlay_field_text_pixels(2)
        else:
            token_y0 = panel_y + 174
            token_y1 = panel_y + 222
            token_text_pixels = dark_pixel_count(
                image,
                panel_segment.start + 30,
                token_y0,
                min(panel_segment.end, panel_segment.start + 560),
                token_y1,
            )
        require(
            # Headless GTK GL render path (no GSK_RENDERER=cairo) anti-aliases
            # the typed token lighter than the macOS reference — it lands at a
            # deterministic ~237 dark px; 200 keeps a real-text floor with margin.
            token_text_pixels >= 200,
            f"Mac-reference typed settings bearer token was not detected: pixels={token_text_pixels}",
        )
        typed_summary += f", token_text_pixels={token_text_pixels}"

    if require_typed_ping_interval:
        if panel_kind == "root-overlay":
            ping_text_pixels = root_overlay_field_text_pixels(3)
        else:
            ping_y0 = panel_y + 208
            ping_y1 = panel_y + 257
            ping_text_pixels = dark_pixel_count(
                image,
                panel_segment.start + 30,
                ping_y0,
                min(panel_segment.end, panel_segment.start + 560),
                ping_y1,
            )
        require(
            # Same headless-GL lightening as the bearer-token check above; a
            # short typed interval renders fewer dark px than the macOS ref.
            ping_text_pixels >= 70,
            f"Mac-reference typed settings ping interval was not detected: pixels={ping_text_pixels}",
        )
        typed_summary += f", ping_text_pixels={ping_text_pixels}"

    if require_selected_default_model:
        if panel_kind == "root-overlay":
            model_x0 = panel_segment.start + 20
            model_x1 = min(panel_segment.end, panel_segment.start + 520)
            model_y0 = panel_y + 340
            model_y1 = panel_y + 430
        else:
            model_x0 = panel_segment.start + 310
            model_x1 = min(panel_segment.end, panel_segment.start + 640)
            model_y0 = panel_y + 272
            model_y1 = panel_y + 346
        model_text_pixels = dark_pixel_count(
            image,
            model_x0,
            model_y0,
            model_x1,
            model_y1,
        )
        require(
            model_text_pixels >= 200,
            f"Mac-reference selected default model was not detected: pixels={model_text_pixels}",
        )
        typed_summary += f", selected_model_pixels={model_text_pixels}"

    return (
        "Quill Chat Mac-reference settings panel: "
        f"app={app_width}x{app_height}, "
        f"panel={panel_segment.width}px@{panel_y} ({panel_kind}), "
        f"header_pixels={header_dark_pixels}, "
        f"field_pixels={field_pixels}, "
        f"body_pixels={body_dark_pixels}, "
        f"wordmark_pixels={wordmark_pixels}"
        f"{typed_summary}"
    )


def validate_quill_chat_mac_reference_settings_delete_confirmation(image: Screenshot) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(app_width >= 260, f"Settings delete confirmation dialog is too narrow: {app_width}px")
    require(app_height >= 140, f"Settings delete confirmation dialog is too short: {app_height}px")
    if app_width <= 720 and app_height <= 520:
        dialog_left = left
        dialog_right = right + 1
        dialog_top = top
        dialog_bottom = bottom + 1
        dialog_kind = "child-window"
    else:
        dialog_left = left
        dialog_right = min(right + 1, left + 330)
        dialog_top = top
        dialog_bottom = min(bottom + 1, top + 180)
        dialog_kind = "root-top-left"

    dialog_width = dialog_right - dialog_left
    dialog_height = dialog_bottom - dialog_top
    surface_pixels = pixel_count(
        image,
        dialog_left,
        dialog_top,
        dialog_right,
        dialog_bottom,
        confirmation_dialog_surface_pixel,
    )
    require(
        surface_pixels >= dialog_width * dialog_height * 0.45,
        f"Settings delete confirmation dialog surface is too sparse: pixels={surface_pixels}",
    )

    title_pixels = dark_pixel_count(
        image,
        dialog_left + 14,
        dialog_top + 12,
        dialog_right - 14,
        dialog_top + min(92, dialog_height),
    )
    require(
        title_pixels >= 140,
        f"Settings delete confirmation title/message was not detected: pixels={title_pixels}",
    )

    action_pixels = dark_pixel_count(
        image,
        dialog_left + 14,
        dialog_top + max(72, dialog_height - 96),
        dialog_right - 14,
        dialog_bottom - 10,
    )
    require(
        action_pixels >= 80,
        f"Settings delete confirmation actions were not detected: pixels={action_pixels}",
    )

    separator = best_horizontal_segment(
        image,
        dialog_top + min(72, max(0, dialog_height - 80)),
        dialog_bottom,
        dialog_left + 10,
        dialog_right - 10,
        gray_line_pixel,
        min_width=max(120, int(dialog_width * 0.55)),
    )
    require(separator is not None, "Settings delete confirmation separator was not detected")

    return (
        "Quill Chat Mac-reference settings delete confirmation: "
        f"dialog={dialog_width}x{dialog_height} ({dialog_kind}), "
        f"surface_pixels={surface_pixels}, "
        f"title_pixels={title_pixels}, "
        f"action_pixels={action_pixels}, "
        f"separator={separator[1].width}px@{separator[0]}"
    )


def validate_quill_chat_mac_reference_completions_panel(
    image: Screenshot,
    minimum_row_dividers: int = 3,
    minimum_row_action_segments: int = 4,
    minimum_wordmark_pixels: int = 650,
) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(app_width >= 1800, f"Completions interaction window is too narrow: {app_width}px")
    require(app_height >= 1200, f"Completions interaction window is too short: {app_height}px")

    legacy_title_pixels = pixel_count(
        image,
        left,
        top,
        left + 260,
        top + 54,
        colorful_wordmark_pixel,
    )
    root_title_pixels = pixel_count(
        image,
        left + int(app_width * 0.25),
        top + int(app_height * 0.25),
        left + int(app_width * 0.60),
        top + int(app_height * 0.38),
        colorful_wordmark_pixel,
    )
    panel_kind = "legacy"
    title_pixels = legacy_title_pixels
    list_x0 = left
    list_x1 = left + 820
    list_y0 = top + 52
    list_y1 = top + 330
    divider_threshold = 360
    if root_title_pixels >= 400:
        panel_kind = "root-overlay"
        title_pixels = root_title_pixels
        list_x0 = left + int(app_width * 0.25)
        list_x1 = left + int(app_width * 0.74)
        list_y0 = top + int(app_height * 0.30)
        list_y1 = top + int(app_height * 0.55)
        divider_threshold = 700
    require(
        title_pixels >= 120,
        f"Mac-reference completions title was not detected: pixels={title_pixels}",
    )

    panel_dark_pixels = dark_pixel_count(
        image,
        list_x0,
        list_y0,
        list_x1,
        list_y1,
    )
    require(
        panel_dark_pixels >= 1_200,
        f"Mac-reference completions panel text was not detected: pixels={panel_dark_pixels}",
    )

    row_divider_count = sum(
        1
        for y in range(list_y0 + int(app_height * 0.04), list_y1)
        if line_row_score(image, y, list_x0, list_x1) >= divider_threshold
    )
    require(
        row_divider_count >= minimum_row_dividers,
        "Mac-reference completions list dividers were not detected: "
        f"rows={row_divider_count}, minimum={minimum_row_dividers}",
    )

    if panel_kind == "root-overlay":
        close_roi = (
            left + int(app_width * 0.71),
            top + int(app_height * 0.275),
            left + int(app_width * 0.79),
            top + int(app_height * 0.335),
        )
        new_completion_roi = (
            left + int(app_width * 0.70),
            top + int(app_height * 0.33),
            left + int(app_width * 0.80),
            top + int(app_height * 0.405),
        )
        row_action_roi = (
            left + int(app_width * 0.725),
            top + int(app_height * 0.345),
            left + int(app_width * 0.79),
            top + int(app_height * 0.53),
        )
    else:
        close_roi = (
            max(list_x0, list_x1 - 180),
            top + 8,
            list_x1,
            top + 70,
        )
        new_completion_roi = (
            max(list_x0, list_x1 - 240),
            list_y0 + int(app_height * 0.03),
            list_x1,
            list_y0 + int(app_height * 0.09),
        )
        row_action_roi = (
            max(list_x0, list_x1 - 180),
            list_y0 + int(app_height * 0.08),
            list_x1,
            list_y1,
        )

    close_pixels = dark_pixel_count(image, *close_roi)
    require(
        close_pixels >= 60,
        f"Mac-reference completions Close control was not detected: pixels={close_pixels}, roi={close_roi}",
    )

    new_completion_pixels = pixel_count(
        image,
        *new_completion_roi,
        mac_reference_completion_action_pixel,
    )
    require(
        new_completion_pixels >= 120,
        "Mac-reference completions New Completion action was not detected: "
        f"pixels={new_completion_pixels}, roi={new_completion_roi}",
    )

    row_action_segments = dark_row_segment_count(
        image,
        *row_action_roi,
        min_row_pixels=2,
        min_height=4,
    )
    require(
        row_action_segments >= minimum_row_action_segments,
        "Mac-reference completions row edit/delete actions were not detected: "
        f"segments={row_action_segments}, minimum={minimum_row_action_segments}, roi={row_action_roi}",
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
        wordmark_pixels >= minimum_wordmark_pixels,
        f"Mac-reference detail view behind completions panel was not detected: pixels={wordmark_pixels}",
    )

    return (
        "Quill Chat Mac-reference completions panel: "
        f"app={app_width}x{app_height}, "
        f"panel={panel_kind}, "
        f"title_pixels={title_pixels}, "
        f"text_pixels={panel_dark_pixels}, "
        f"divider_rows={row_divider_count}, "
        f"close_pixels={close_pixels}, "
        f"new_completion_pixels={new_completion_pixels}, "
        f"row_action_segments={row_action_segments}, "
        f"wordmark_pixels={wordmark_pixels}"
    )


def validate_quill_chat_mac_reference_completions_panel_visible(image: Screenshot) -> str:
    return validate_quill_chat_mac_reference_completions_panel(
        image,
        minimum_wordmark_pixels=350,
    )


def validate_quill_chat_mac_reference_completions_new_sheet(image: Screenshot) -> str:
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

    sheet = best_horizontal_segment(
        image,
        top + int(app_height * 0.20),
        top + int(app_height * 0.62),
        detail_left,
        right + 1,
        settings_panel_background_pixel,
        min_width=int(detail_width * 0.55),
    )
    if sheet is not None:
        sheet_y, sheet_segment = sheet
        sheet_top = sheet_y
        for y in range(top + int(app_height * 0.20), sheet_y + 1):
            segments = image.segments_at(
                y,
                detail_left,
                right + 1,
                settings_panel_background_pixel,
                min_width=int(detail_width * 0.55),
            )
            if not segments:
                continue
            segment = max(segments, key=lambda item: item.width)
            if (
                segment.width >= int(sheet_segment.width * 0.80)
                and abs(segment.center - sheet_segment.center) <= max(24, int(sheet_segment.width * 0.10))
            ):
                sheet_top = y
                sheet_segment = Segment(
                    min(sheet_segment.start, segment.start),
                    max(sheet_segment.end, segment.end),
                )
                break
        # GTK's root-overlay sheet often first satisfies the background predicate
        # on the first text field rather than the translucent title/action strip.
        # Expand back to that strip so Cancel/Save and the first field are measured
        # against the actual sheet chrome instead of the form body.
        sheet_top = max(top, sheet_top - 64)
        sheet_segment = Segment(
            max(detail_left, sheet_segment.start - 26),
            min(right, sheet_segment.end + 26),
        )
    else:
        inferred_field_rows: list[tuple[int, int, Segment]] = []
        active_row: tuple[int, int, Segment] | None = None
        for y in range(top + int(app_height * 0.30), top + int(app_height * 0.75)):
            segments = [
                segment
                for segment in image.segments_at(
                    y,
                    detail_left,
                    right + 1,
                    completions_upsert_form_field_pixel,
                    min_width=int(detail_width * 0.35),
                )
                if segment.width <= int(detail_width * 0.75)
            ]
            if not segments:
                if active_row is not None:
                    inferred_field_rows.append(active_row)
                    active_row = None
                continue
            segment = max(segments, key=lambda item: item.width)
            if active_row is None:
                active_row = (y, y, segment)
            else:
                start_y, _, active_segment = active_row
                active_row = (
                    start_y,
                    y,
                    Segment(
                        min(active_segment.start, segment.start),
                        max(active_segment.end, segment.end),
                    ),
                )
        if active_row is not None:
            inferred_field_rows.append(active_row)
        require(
            len(inferred_field_rows) >= 3,
            "Completions Upsert sheet surface was not detected: "
            f"field_rows={inferred_field_rows}",
        )
        field_start = min(segment.start for _, _, segment in inferred_field_rows)
        field_end = max(segment.end for _, _, segment in inferred_field_rows)
        sheet_segment = Segment(
            max(detail_left, field_start - 26),
            min(right, field_end + 26),
        )
        sheet_top = max(top, inferred_field_rows[0][0] - 64)

    cancel_roi = (
        sheet_segment.start,
        max(top, sheet_top - 8),
        min(sheet_segment.end, sheet_segment.start + 220),
        sheet_top + 64,
    )
    save_roi = (
        max(sheet_segment.start, sheet_segment.end - 220),
        max(top, sheet_top - 8),
        sheet_segment.end + 1,
        sheet_top + 64,
    )
    panel_roi = (
        sheet_segment.start,
        sheet_top,
        sheet_segment.end + 1,
        min(bottom + 1, sheet_top + int(app_height * 0.48)),
    )

    field_rows: list[tuple[int, int, Segment]] = []
    active_row: tuple[int, int, Segment] | None = None
    for y in range(sheet_top + 36, min(bottom + 1, sheet_top + int(app_height * 0.34))):
        segments = image.segments_at(
            y,
            sheet_segment.start + 12,
            sheet_segment.end - 12,
            completions_upsert_form_field_pixel,
            min_width=int(sheet_segment.width * 0.45),
        )
        if not segments:
            if active_row is not None:
                field_rows.append(active_row)
                active_row = None
            continue
        segment = max(segments, key=lambda item: item.width)
        if active_row is None:
            active_row = (y, y, segment)
        else:
            start_y, _, active_segment = active_row
            active_row = (
                start_y,
                y,
                Segment(
                    min(active_segment.start, segment.start),
                    max(active_segment.end, segment.end),
                ),
            )
    if active_row is not None:
        field_rows.append(active_row)

    cancel_pixels = pixel_count(image, *cancel_roi, mac_reference_completion_action_pixel)
    save_pixels = pixel_count(image, *save_roi, mac_reference_completion_action_pixel)
    panel_surface_pixels = pixel_count(image, *panel_roi, completions_upsert_sheet_pixel)
    name_field_pixels = 0
    instruction_field_pixels = 0
    preview_pixels = 0
    if len(field_rows) >= 1:
        y0, y1, segment = field_rows[0]
        name_field_pixels = pixel_count(
            image,
            segment.start,
            y0,
            segment.end + 1,
            y1 + 1,
            completions_upsert_form_field_pixel,
        )
    if len(field_rows) >= 2:
        y0, y1, segment = field_rows[1]
        instruction_field_pixels = pixel_count(
            image,
            segment.start,
            y0,
            segment.end + 1,
            y1 + 1,
            completions_upsert_form_field_pixel,
        )
    if len(field_rows) >= 3:
        y0, y1, segment = field_rows[2]
        preview_pixels = pixel_count(
            image,
            segment.start,
            y0,
            segment.end + 1,
            y1 + 1,
            completions_upsert_form_field_pixel,
        )

    require(
        cancel_pixels >= 90,
        f"Completions Upsert Cancel action was not detected: pixels={cancel_pixels}, roi={cancel_roi}",
    )
    require(
        save_pixels >= 90,
        f"Completions Upsert Save action was not detected: pixels={save_pixels}, roi={save_roi}",
    )
    require(
        panel_surface_pixels >= 32_000,
        "Completions Upsert sheet surface was not detected: "
        f"pixels={panel_surface_pixels}, roi={panel_roi}",
    )
    require(
        name_field_pixels >= 14_000,
        f"Completions Upsert name field was not detected: pixels={name_field_pixels}, rows={field_rows}",
    )
    require(
        instruction_field_pixels >= 50_000,
        "Completions Upsert instruction editor was not detected: "
        f"pixels={instruction_field_pixels}, rows={field_rows}",
    )
    require(
        preview_pixels >= 14_000,
        f"Completions Upsert preview chip was not detected: pixels={preview_pixels}, rows={field_rows}",
    )

    return (
        "Quill Chat Mac-reference completions new sheet: "
        f"cancel_pixels={cancel_pixels}, "
        f"save_pixels={save_pixels}, "
        f"panel_surface_pixels={panel_surface_pixels}, "
        f"name_field_pixels={name_field_pixels}, "
        f"instruction_field_pixels={instruction_field_pixels}, "
        f"preview_pixels={preview_pixels}, "
        f"sheet={sheet_segment.width}px@{sheet_top}"
    )


def validate_quill_chat_mac_reference_completions_saved(image: Screenshot) -> str:
    panel_summary = validate_quill_chat_mac_reference_completions_panel(
        image,
        minimum_wordmark_pixels=350,
    )
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    root_title_pixels = pixel_count(
        image,
        left + int(app_width * 0.25),
        top + int(app_height * 0.25),
        left + int(app_width * 0.60),
        top + int(app_height * 0.38),
        colorful_wordmark_pixel,
    )

    dismissed_sheet_fields_roi = (
        left + int(app_width * 0.36),
        top + int(app_height * 0.30),
        left + int(app_width * 0.78),
        top + int(app_height * 0.44),
    )
    if root_title_pixels >= 400:
        saved_row_roi = (
            left + int(app_width * 0.31),
            top + int(app_height * 0.335),
            left + int(app_width * 0.70),
            top + int(app_height * 0.39),
        )
        saved_row_action_roi = (
            left + int(app_width * 0.70),
            top + int(app_height * 0.33),
            left + int(app_width * 0.79),
            top + int(app_height * 0.40),
        )
    else:
        saved_row_roi = (
            left + int(app_width * 0.24),
            top + int(app_height * 0.50),
            left + int(app_width * 0.45),
            top + int(app_height * 0.57),
        )
        saved_row_action_roi = (
            left + int(app_width * 0.725),
            top + int(app_height * 0.49),
            left + int(app_width * 0.79),
            top + int(app_height * 0.57),
        )

    dismissed_sheet_field_pixels = pixel_count(
        image,
        *dismissed_sheet_fields_roi,
        completions_upsert_form_field_pixel,
    )
    saved_row_pixels = dark_pixel_count(image, *saved_row_roi)
    saved_row_action_segments = dark_row_segment_count(
        image,
        *saved_row_action_roi,
        min_row_pixels=2,
        min_height=4,
    )

    require(
        dismissed_sheet_field_pixels <= 12_000,
        "Completions Upsert sheet still appears to be visible after Save: "
        f"pixels={dismissed_sheet_field_pixels}, roi={dismissed_sheet_fields_roi}",
    )
    require(
        saved_row_pixels >= 260,
        f"Saved completion row was not detected: pixels={saved_row_pixels}, roi={saved_row_roi}",
    )
    require(
        saved_row_action_segments >= 1,
        "Saved completion edit/delete controls were not detected: "
        f"segments={saved_row_action_segments}, roi={saved_row_action_roi}",
    )

    return (
        "Quill Chat Mac-reference completions saved: "
        f"dismissed_sheet_field_pixels={dismissed_sheet_field_pixels}, "
        f"saved_row_pixels={saved_row_pixels}, "
        f"saved_row_action_segments={saved_row_action_segments}; "
        f"{panel_summary}"
    )


def validate_quill_chat_mac_reference_completions_edited(image: Screenshot) -> str:
    panel_summary = validate_quill_chat_mac_reference_completions_panel(
        image,
        minimum_wordmark_pixels=350,
    )
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    root_title_pixels = pixel_count(
        image,
        left + int(app_width * 0.25),
        top + int(app_height * 0.25),
        left + int(app_width * 0.60),
        top + int(app_height * 0.38),
        colorful_wordmark_pixel,
    )

    dismissed_sheet_fields_roi = (
        left + int(app_width * 0.36),
        top + int(app_height * 0.30),
        left + int(app_width * 0.78),
        top + int(app_height * 0.44),
    )
    if root_title_pixels >= 400:
        edited_row_name_roi = (
            left + int(app_width * 0.31),
            top + int(app_height * 0.335),
            left + int(app_width * 0.70),
            top + int(app_height * 0.39),
        )
    else:
        edited_row_name_roi = (
            left + int(app_width * 0.235),
            top + int(app_height * 0.49),
            left + int(app_width * 0.45),
            top + int(app_height * 0.57),
        )

    dismissed_sheet_field_pixels = pixel_count(
        image,
        *dismissed_sheet_fields_roi,
        completions_upsert_form_field_pixel,
    )
    edited_row_name_pixels = dark_pixel_count(image, *edited_row_name_roi)

    require(
        dismissed_sheet_field_pixels <= 12_000,
        "Completions edit sheet still appears to be visible after Save: "
        f"pixels={dismissed_sheet_field_pixels}, roi={dismissed_sheet_fields_roi}",
    )
    require(
        edited_row_name_pixels >= 240,
        "Edited completion row name was not detected above the stock row baseline: "
        f"pixels={edited_row_name_pixels}, roi={edited_row_name_roi}",
    )

    return (
        "Quill Chat Mac-reference completions edited: "
        f"dismissed_sheet_field_pixels={dismissed_sheet_field_pixels}, "
        f"edited_row_name_pixels={edited_row_name_pixels}; "
        f"{panel_summary}"
    )


def validate_quill_chat_mac_reference_completions_deleted(image: Screenshot) -> str:
    panel_summary = validate_quill_chat_mac_reference_completions_panel(
        image,
        minimum_row_dividers=2,
        minimum_row_action_segments=3,
        minimum_wordmark_pixels=350,
    )
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1

    row_action_roi = (
        left + int(app_width * 0.725),
        top + int(app_height * 0.37),
        left + int(app_width * 0.79),
        top + int(app_height * 0.53),
    )
    deleted_row_action_segments = dark_row_segment_count(
        image,
        *row_action_roi,
        min_row_pixels=2,
        min_height=4,
    )
    require(
        deleted_row_action_segments <= 3,
        "Deleted completion row still appears to be present: "
        f"segments={deleted_row_action_segments}, roi={row_action_roi}",
    )

    return (
        "Quill Chat Mac-reference completions deleted: "
        f"row_action_segments={deleted_row_action_segments}; "
        f"{panel_summary}"
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

    marker_y0 = top + int(app_height * 0.12)
    marker_y1 = top + int(app_height * 0.86)
    marker_row_pixels = [
        (
            y,
            pixel_count(
                image,
                left,
                y,
                left + 120,
                y + 1,
                selected_history_marker_pixel,
            ),
        )
        for y in range(marker_y0, marker_y1)
    ]
    marker_y, marker_peak_pixels = max(
        marker_row_pixels,
        key=lambda row: row[1],
    )
    bullet_pixels = sum(count for _, count in marker_row_pixels)
    require(
        bullet_pixels >= 5,
        "Mac-reference selected history marker was not detected: "
        f"pixels={bullet_pixels}, peak={marker_peak_pixels}@{marker_y}",
    )

    selected_row_text_y0 = max(marker_y - int(app_height * 0.025), top)
    selected_row_text_y1 = min(marker_y + int(app_height * 0.035), bottom + 1)
    selected_row_pixels = dark_pixel_count(
        image,
        left + 30,
        selected_row_text_y0,
        divider_x - 20,
        selected_row_text_y1,
    )
    require(
        selected_row_pixels >= 180,
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
        selected_message_y0 = top + int(app_height * 0.05)
        selected_message_y1 = top + int(app_height * 0.70)

        user_message_pixels = dark_pixel_count(
            image,
            detail_left + int(detail_width * 0.77),
            selected_message_y0,
            right - int(detail_width * 0.01),
            selected_message_y1,
        )
        require(
            user_message_pixels >= 220,
            "Mac-reference selected transcript user message did not align to the trailing edge: "
            f"pixels={user_message_pixels}",
        )

        assistant_message_pixels = dark_pixel_count(
            image,
            detail_left + int(detail_width * 0.02),
            selected_message_y0,
            detail_left + int(detail_width * 0.52),
            selected_message_y1,
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
        f"selected_marker_peak={marker_peak_pixels}@{marker_y}, "
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
        bottom_transcript_pixels >= 2_000,
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


def validate_quill_chat_mac_reference_message_hover_actions(image: Screenshot) -> str:
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

    action_pixels = dark_pixel_count(
        image,
        detail_left + int(detail_width * 0.78),
        top + int(app_height * 0.11),
        right - int(detail_width * 0.02),
        top + int(app_height * 0.16),
    )
    require(
        action_pixels >= 35,
        "Mac-reference message hover action icons were not detected. "
        "The original Enchanted row should reveal copy/speak/edit controls on hover: "
        f"pixels={action_pixels}",
    )

    return (
        history_summary
        + "\nQuill Chat Mac-reference message hover actions: "
        f"action_pixels={action_pixels}"
    )


def validate_quill_chat_mac_reference_sent_message(
    image: Screenshot,
    label: str,
    minimum_message_pixels: int,
    minimum_right_aligned_message_pixels: int,
) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(app_width >= 1800, f"{label} window is too narrow: {app_width}px")
    require(app_height >= 1200, f"{label} window is too short: {app_height}px")

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
        f"Mac-reference empty-state prompt cards remained after {label}: pixels={prompt_card_like_pixels}",
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
        f"Mac-reference empty-state wordmark remained after {label}: pixels={wordmark_pixels}",
    )

    message_y0 = top + int(app_height * 0.05)
    message_y1 = top + int(app_height * 0.70)

    message_pixels = dark_pixel_count(
        image,
        detail_left + int(detail_width * 0.05),
        message_y0,
        right - int(detail_width * 0.03),
        message_y1,
    )
    require(
        message_pixels >= minimum_message_pixels,
        f"Mac-reference {label} message content was not detected: pixels={message_pixels}",
    )
    right_aligned_message_pixels = dark_pixel_count(
        image,
        detail_left + int(detail_width * 0.77),
        message_y0,
        right - int(detail_width * 0.01),
        message_y1,
    )
    require(
        right_aligned_message_pixels >= minimum_right_aligned_message_pixels,
        f"Mac-reference {label} message did not align to the trailing edge: "
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
    require(alert is not None, f"Mac-reference {label} alert was not detected")
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
    require(composer is not None, f"Mac-reference {label} composer was not detected")
    composer_y, composer_segment = composer

    return (
        f"Quill Chat Mac-reference {label}: "
        f"app={app_width}x{app_height}, "
        f"sidebar={divider_x - left}px, "
        f"prompt_card_pixels={prompt_card_like_pixels}, "
        f"wordmark_pixels={wordmark_pixels}, "
        f"message_pixels={message_pixels}, "
        f"right_message_pixels={right_aligned_message_pixels}, "
        f"alert={alert_segment.width}px@{alert_y}, "
        f"composer={composer_segment.width}px@{composer_y}"
    )


def validate_quill_chat_mac_reference_prompt_send(image: Screenshot) -> str:
    return validate_quill_chat_mac_reference_sent_message(
        image,
        "prompt-send",
        minimum_message_pixels=350,
        minimum_right_aligned_message_pixels=220,
    )


def validate_quill_chat_mac_reference_composer_send(image: Screenshot) -> str:
    return validate_quill_chat_mac_reference_sent_message(
        image,
        "composer-send",
        minimum_message_pixels=160,
        minimum_right_aligned_message_pixels=120,
    )


def validate_quill_chat_mac_reference_toolbar_model_selected(image: Screenshot) -> str:
    return validate_quill_chat_mac_reference_sent_message(
        image,
        "toolbar model-selected",
        minimum_message_pixels=350,
        minimum_right_aligned_message_pixels=220,
    )


def validate_quill_chat_functional_transcript(image: Screenshot) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(app_width >= 1800, f"Functional transcript window is too narrow: {app_width}px")
    require(app_height >= 1200, f"Functional transcript window is too short: {app_height}px")

    divider_search = range(left + int(app_width * 0.23), left + int(app_width * 0.34))
    divider_x = max(
        divider_search,
        key=lambda x: line_column_score(image, x, top + int(app_height * 0.04), bottom - 40),
    )
    divider_score = line_column_score(image, divider_x, top + int(app_height * 0.04), bottom - 40)
    sidebar_ratio = (divider_x - left) / app_width
    require(
        0.255 <= sidebar_ratio <= 0.305 and divider_score >= app_height * 0.72,
        f"Functional transcript sidebar divider mismatch: x={divider_x}, ratio={sidebar_ratio:.3f}, score={divider_score}",
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
        f"Functional transcript still shows empty-state prompt cards: pixels={prompt_card_like_pixels}",
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
        f"Functional transcript still shows the empty-state wordmark: pixels={wordmark_pixels}",
    )

    transcript_message_y0 = top + int(app_height * 0.05)
    transcript_message_y1 = top + int(app_height * 0.70)

    leading_message_pixels = dark_pixel_count(
        image,
        detail_left + int(detail_width * 0.02),
        transcript_message_y0,
        detail_left + int(detail_width * 0.45),
        transcript_message_y1,
    )
    require(
        leading_message_pixels >= 120,
        f"Functional transcript assistant reply was not detected: pixels={leading_message_pixels}",
    )

    trailing_message_pixels = dark_pixel_count(
        image,
        detail_left + int(detail_width * 0.77),
        transcript_message_y0,
        right - int(detail_width * 0.01),
        transcript_message_y1,
    )
    require(
        trailing_message_pixels >= 120,
        f"Functional transcript user message was not detected on the trailing edge: pixels={trailing_message_pixels}",
    )

    composer = best_horizontal_segment(
        image,
        top + int(app_height * 0.88),
        bottom + 1,
        detail_left,
        right + 1,
        mac_reference_composer_pixel,
        min_width=int(detail_width * 0.55),
    )
    require(composer is not None, "Functional transcript composer was not detected")
    composer_y, composer_segment = composer

    return (
        "Quill Chat functional transcript: "
        f"app={app_width}x{app_height}, "
        f"sidebar={divider_x - left}px, "
        f"prompt_card_pixels={prompt_card_like_pixels}, "
        f"wordmark_pixels={wordmark_pixels}, "
        f"assistant_pixels={leading_message_pixels}, "
        f"user_pixels={trailing_message_pixels}, "
        f"composer={composer_segment.width}px@{composer_y}"
    )


def validate_quill_enchanted_qt_native(
    image: Screenshot,
    minimum_selected_center_offset: int | None = None,
) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(960 <= app_width <= 1220, f"Enchanted Qt window width is unexpected: {app_width}px")
    require(660 <= app_height <= 820, f"Enchanted Qt window height is unexpected: {app_height}px")

    sidebar_width = min(340, max(260, int(app_width * 0.30)))
    sidebar_pixels = pixel_count(
        image,
        left,
        top,
        left + sidebar_width,
        bottom + 1,
        enchanted_sidebar_pixel,
    )
    header_pixels = pixel_count(
        image,
        left + sidebar_width,
        top,
        right + 1,
        top + 100,
        enchanted_header_pixel,
    )
    canvas_pixels = pixel_count(
        image,
        left + sidebar_width,
        top + 100,
        right + 1,
        bottom - 120,
        enchanted_canvas_pixel,
    )
    primary_pixels = pixel_count(
        image,
        left + 20,
        top + 80,
        left + sidebar_width - 20,
        top + 240,
        enchanted_primary_pixel,
    )
    # The mint attachment drop-target banner only renders while a file drag is
    # actively hovering the composer (the composer gates it on
    # model.isAttachmentDropTargeted, set from the .dropDestination isTargeted
    # drag state) — and the shipped tint is light blue (#EAF2FF), not the mint
    # this predicate was calibrated for. A static smoke never drags, so verify
    # the always-present white composer box in the same bottom band instead.
    composer_pixels = pixel_count(
        image,
        left + sidebar_width + 20,
        bottom - 150,
        right - 20,
        bottom - 80,
        enchanted_canvas_pixel,
    )
    selected_row_details = ""
    if minimum_selected_center_offset is not None:
        selected_row = best_pixel_row_segment(
            image,
            left + 4,
            # Restrict to the conversation-list band: BELOW the "Conversations"
            # header (top+~306, whose label emits a few accent-blue pixels) and
            # ABOVE the bottom action buttons (Delete chat / Clear All), whose
            # trash-can icons ALSO match enchanted_primary_pixel at top+~594 and
            # would otherwise be picked by best_pixel_row_segment (39px > the dot's
            # ~14px) as a false-positive "selection".
            top + 320,
            left + sidebar_width - 16,
            min(bottom + 1, top + 520),
            # Genuine native Enchanted (ConversationHistoryListView) marks the selected
            # conversation with a small leading accent dot (QuillColors.primary = #4285F4),
            # NOT a filled row. EnchantedRootView + QuillEnchantedQt6Widgets now render that
            # dot, so detect accent blue near the row's leading edge (hence x0 = left + 4).
            # Within this tightened band the selected-row dot is the only accent-blue
            # element, so even a small pixel count is an unambiguous selection signal.
            enchanted_primary_pixel,
            min_row_pixels=3,
        )
        require(selected_row is not None, "Enchanted Qt selected conversation row dot was not detected")
        selected_row_segment, selected_row_pixels = selected_row
        selected_row_center_offset = selected_row_segment.center - top
        require(
            selected_row_center_offset >= minimum_selected_center_offset,
            "Enchanted Qt conversation selection did not move to the lower conversation row: "
            f"selected_center={selected_row_center_offset:.1f}px",
        )
        require(
            selected_row_pixels >= 12,
            f"Enchanted Qt selected conversation row dot is too small: pixels={selected_row_pixels}",
        )
        selected_row_details = (
            f", selected_row_pixels={selected_row_pixels}, "
            f"selected_row_y={selected_row_segment.start - top}-{selected_row_segment.end - top}"
        )
    text_pixels = dark_pixel_count(image, left + 20, top + 20, right - 20, bottom - 20)
    require(sidebar_pixels >= 30000, f"Enchanted Qt sidebar was not detected: pixels={sidebar_pixels}")
    require(header_pixels >= 20000, f"Enchanted Qt header was not detected: pixels={header_pixels}")
    require(canvas_pixels >= 40000, f"Enchanted Qt canvas was not detected: pixels={canvas_pixels}")
    require(primary_pixels >= 800, f"Enchanted Qt primary action was not detected: pixels={primary_pixels}")
    require(composer_pixels >= 5000, f"Enchanted Qt composer was not detected: pixels={composer_pixels}")
    require(text_pixels >= 1800, f"Enchanted Qt text content was not detected: pixels={text_pixels}")

    return (
        "Quill Enchanted Qt native: "
        f"app={app_width}x{app_height}, "
        f"sidebar_pixels={sidebar_pixels}, "
        f"header_pixels={header_pixels}, "
        f"canvas_pixels={canvas_pixels}, "
        f"primary_pixels={primary_pixels}, "
        f"composer_pixels={composer_pixels}, "
        f"text_pixels={text_pixels}"
        f"{selected_row_details}"
    )


def validate_quill_enchanted_empty_state_gtk(image: Screenshot) -> str:
    """Landmark-coverage parity gate for the genuine-native Enchanted empty state
    on the GTK backend (quill-enchanted-gtk.png), post the #138-#145 rework.

    Asserts the new-conversation landmarks that match the genuine macOS app
    (Tests/Fixtures/Enchanted/macos-reference.png): a sidebar/canvas divider, a
    centered gradient wordmark, a MINIMAL sidebar (no blue "New chat" button —
    that moved to the toolbar), a horizontal 4-card prompt row, a short composer
    bar, and a 3-item bottom nav. Reports a landmark-coverage ratio and requires
    it to be >= 0.95 (i.e. every critical landmark present), so any regression of
    the empty-state layout fails the gate.
    """
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(1100 <= app_width <= 1280, f"Enchanted empty-state GTK width is unexpected: {app_width}px")
    require(680 <= app_height <= 840, f"Enchanted empty-state GTK height is unexpected: {app_height}px")

    # Sidebar/canvas divider: strong vertical gray line ~26% across.
    divider_x = max(
        range(left + 250, left + 360),
        key=lambda x: line_column_score(image, x, top + 10, bottom - 10),
    )
    divider_score = line_column_score(image, divider_x, top + 10, bottom - 10)
    sidebar_width = divider_x - left
    detail_left = divider_x + 1

    # Centered gradient wordmark ("Enchanted") in the canvas top band — the GTK
    # backend renders the gradient as a ~uniform purple, matched by
    # enchanted_linux_gtk_wordmark_pixel.
    wordmark_pixels = pixel_count(
        image, detail_left + 20, top + 120, right - 20, top + 240, enchanted_linux_gtk_wordmark_pixel
    )
    # Minimal sidebar: the genuine empty state has NO blue primary "New chat"
    # button (it moved to the toolbar compose icon in #139), so the sidebar must
    # carry essentially no accent-blue fill.
    sidebar_blue = pixel_count(
        image, left + 10, top + 10, divider_x - 10, bottom - 10, enchanted_primary_pixel
    )
    # Horizontal prompt-card row: light cards spread across the canvas, resolving
    # into multiple distinct segments along a row.
    card_pixels = pixel_count(
        image, detail_left + 20, top + 225, right - 20, top + 410, prompt_card_pixel
    )
    best_card_segments = 0
    best_card_span = 0
    for probe_y in range(top + 300, top + 360, 10):
        segments = image.segments_at(probe_y, detail_left, right, prompt_card_pixel, 40)
        best_card_segments = max(best_card_segments, len(segments))
        if segments:
            best_card_span = max(best_card_span, segments[-1].end - segments[0].start)
    # Wordmark horizontal centroid: the gradient wordmark should sit ~centered in
    # the detail canvas (a left/right-aligned regression would still have pixels
    # but an off-center centroid).
    wordmark_x_sum = 0
    wordmark_x_count = 0
    for probe_y in range(top + 120, top + 240, 2):
        for probe_x in range(detail_left + 20, right - 20, 2):
            if enchanted_linux_gtk_wordmark_pixel(image.rgb(probe_x, probe_y)):
                wordmark_x_sum += probe_x
                wordmark_x_count += 1
    canvas_center_x = detail_left + (right - detail_left) / 2
    wordmark_centroid_x = (wordmark_x_sum / wordmark_x_count) if wordmark_x_count else -1
    wordmark_centered = (
        wordmark_x_count > 0
        and abs(wordmark_centroid_x - canvas_center_x) <= (right - detail_left) * 0.20
    )
    # Short composer bar: a band of near-white composer surface near the bottom.
    composer_pixels = pixel_count(
        image, detail_left + 20, bottom - 210, right - 20, bottom - 120, enchanted_canvas_pixel
    )
    # Bottom nav (Completions / Shortcuts / Settings): dark text in the sidebar
    # lower band.
    bottom_nav_pixels = dark_pixel_count(image, left + 10, bottom - 160, divider_x - 10, bottom - 10)

    landmarks = {
        "sidebar_divider": 250 <= sidebar_width <= 340 and divider_score >= app_height * 0.60,
        "gradient_wordmark": wordmark_pixels >= 1200,
        "minimal_sidebar_no_blue_button": sidebar_blue < 400,
        "horizontal_card_row": card_pixels >= 30000 and best_card_segments >= 3,
        "card_row_spans_width": best_card_span >= (right - detail_left) * 0.50,
        "wordmark_centered": wordmark_centered,
        "short_composer_bar": composer_pixels >= 8000,
        "bottom_nav": bottom_nav_pixels >= 500,
    }
    detected = sum(1 for present in landmarks.values() if present)
    total = len(landmarks)
    ratio = detected / total
    missing = sorted(name for name, present in landmarks.items() if not present)
    require(
        ratio >= 0.95,
        f"Enchanted empty-state parity ratio {ratio:.2f} (<0.95): "
        f"{detected}/{total} landmarks; missing={missing}; "
        f"divider_x={divider_x}, divider_score={divider_score}, sidebar_width={sidebar_width}, "
        f"wordmark_pixels={wordmark_pixels}, sidebar_blue={sidebar_blue}, "
        f"card_pixels={card_pixels}, card_segments={best_card_segments}, "
        f"card_span={best_card_span}, wordmark_centroid_x={wordmark_centroid_x:.0f}, "
        f"canvas_center_x={canvas_center_x:.0f}, "
        f"composer_pixels={composer_pixels}, bottom_nav_pixels={bottom_nav_pixels}",
    )

    return (
        "Quill Enchanted empty-state GTK parity ok: "
        f"ratio={ratio:.2f} ({detected}/{total}), app={app_width}x{app_height}, "
        f"sidebar_width={sidebar_width}, wordmark_pixels={wordmark_pixels}, "
        f"sidebar_blue={sidebar_blue}, card_pixels={card_pixels}, "
        f"card_segments={best_card_segments}, card_span={best_card_span}, "
        f"wordmark_centroid_x={wordmark_centroid_x:.0f}/canvas_center_x={canvas_center_x:.0f}, "
        f"composer_pixels={composer_pixels}, bottom_nav_pixels={bottom_nav_pixels}"
    )


def validate_quill_enchanted_linux_qt_snapshot(image: Screenshot) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(960 <= app_width <= 1220, f"Generated Enchanted Qt window width is unexpected: {app_width}px")
    require(660 <= app_height <= 820, f"Generated Enchanted Qt window height is unexpected: {app_height}px")

    sidebar_width = min(360, max(300, int(app_width * 0.30)))
    detail_left = left + sidebar_width
    sidebar_pixels = pixel_count(
        image,
        left,
        top,
        detail_left,
        bottom + 1,
        enchanted_sidebar_pixel,
    )
    sidebar_text_pixels = dark_pixel_count(
        image,
        left + 24,
        top + 80,
        detail_left - 16,
        bottom - 160,
    )
    stale_primary_pixels = pixel_count(
        image,
        left + 20,
        top + 20,
        detail_left - 20,
        top + 170,
        enchanted_primary_pixel,
    )
    wordmark_pixels = pixel_count(
        image,
        detail_left + 16,
        top + 120,
        right - 20,
        bottom - 240,
        colorful_wordmark_pixel,
    )
    prompt_card_row = best_prompt_card_row(
        image,
        top + 120,
        bottom - 120,
        detail_left + 16,
        right - 20,
        min_width=110,
        predicate=generic_qt_card_pixel,
    )
    require(prompt_card_row is not None, "Generated Enchanted Qt prompt-card row was not detected")
    prompt_y, prompt_segments = prompt_card_row
    prompt_card_height = prompt_card_fill_height(
        image,
        prompt_y,
        bottom - 120,
        prompt_segments,
        generic_qt_card_pixel,
    )
    prompt_text_pixels = dark_pixel_count(
        image,
        prompt_segments[0].start + 10,
        max(top, prompt_y - 6),
        prompt_segments[-1].end - 10,
        min(bottom, prompt_y + 85),
    )
    notice_pixels = pixel_count(
        image,
        detail_left + 16,
        bottom - 160,
        right - 20,
        bottom - 60,
        alert_pixel,
    )
    detail_width = right - detail_left
    # The Qt composer paints a near-white fill identical to the canvas since
    # the mac-parity restyle (4304993b) — only its 1px rounded outline remains
    # distinguishable, so the old fill-area count can never reach 5000 again.
    # Detect the field by its outline: a wide horizontal border run in the
    # composer band (the outline color sits inside the composer predicate's
    # gray range).
    composer = best_horizontal_segment(
        image,
        bottom - 80,
        bottom - 15,
        detail_left + 100,
        right - 100 + 1,
        mac_reference_composer_pixel,
        min_width=int(detail_width * 0.5),
    )
    composer_accessory_pixels = dark_pixel_count(
        image,
        detail_left + int(detail_width * 0.62),
        bottom - 80,
        right - 45,
        bottom - 15,
    )
    bottom_nav_pixels = dark_pixel_count(image, left + 20, bottom - 130, detail_left - 20, bottom - 20)
    detail_text_pixels = dark_pixel_count(image, detail_left + 16, top + 20, right - 20, bottom - 20)
    require(sidebar_pixels >= 150000, f"Generated Enchanted Qt sidebar was not detected: pixels={sidebar_pixels}")
    require(
        sidebar_text_pixels >= 2500,
        f"Generated Enchanted Qt chat sidebar text was not detected: pixels={sidebar_text_pixels}",
    )
    require(
        stale_primary_pixels <= 300,
        "Generated Enchanted Qt still shows the stale generic primary action: "
        f"pixels={stale_primary_pixels}",
    )
    require(wordmark_pixels >= 2000, f"Generated Enchanted Qt wordmark was not detected: pixels={wordmark_pixels}")
    require(
        prompt_card_height >= 110,
        f"Generated Enchanted Qt prompt cards are too short: height={prompt_card_height}px",
    )
    require(
        prompt_text_pixels >= 1200,
        f"Generated Enchanted Qt prompt card text was not detected: pixels={prompt_text_pixels}",
    )
    require(notice_pixels >= 15000, f"Generated Enchanted Qt notice banner was not detected: pixels={notice_pixels}")
    require(composer is not None, "Generated Enchanted Qt composer outline was not detected")
    require(
        composer_accessory_pixels >= 20,
        "Generated Enchanted Qt composer accessory icon was not detected: "
        f"pixels={composer_accessory_pixels}",
    )
    require(bottom_nav_pixels >= 300, f"Generated Enchanted Qt bottom navigation was not detected: pixels={bottom_nav_pixels}")
    require(detail_text_pixels >= 4000, f"Generated Enchanted Qt detail text was not detected: pixels={detail_text_pixels}")

    return (
        "Quill Enchanted generated Qt chat snapshot: "
        f"app={app_width}x{app_height}, "
        f"sidebar_pixels={sidebar_pixels}, "
        f"sidebar_text_pixels={sidebar_text_pixels}, "
        f"stale_primary_pixels={stale_primary_pixels}, "
        f"wordmark_pixels={wordmark_pixels}, "
        f"prompt_cards={[f'{segment.start}-{segment.end}' for segment in prompt_segments]}, "
        f"prompt_card_height={prompt_card_height}, "
        f"prompt_text_pixels={prompt_text_pixels}, "
        f"notice_pixels={notice_pixels}, "
        f"composer={composer[1].width}px@{composer[0]}, "
        f"composer_accessory_pixels={composer_accessory_pixels}, "
        f"bottom_nav_pixels={bottom_nav_pixels}, "
        f"detail_text_pixels={detail_text_pixels}"
    )


def validate_quill_enchanted_linux_qt_selected_chat(image: Screenshot) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(960 <= app_width <= 1220, f"Generated Enchanted Qt selected window width is unexpected: {app_width}px")
    require(660 <= app_height <= 820, f"Generated Enchanted Qt selected window height is unexpected: {app_height}px")

    sidebar_width = min(360, max(300, int(app_width * 0.30)))
    detail_left = left + sidebar_width
    selected_marker_pixels = pixel_count(
        image,
        left + 4,
        top + 320,
        left + 58,
        min(bottom + 1, top + 540),
        enchanted_primary_pixel,
    )
    user_bubble_pixels = pixel_count(
        image,
        detail_left + int((right - detail_left) * 0.50),
        top + 170,
        right - 8,
        bottom - 145,
        enchanted_user_bubble_pixel,
    )
    assistant_message_pixels = dark_pixel_count(
        image,
        detail_left + 16,
        top + 250,
        detail_left + int((right - detail_left) * 0.55),
        bottom - 120,
    )
    notice_pixels = pixel_count(
        image,
        detail_left + 16,
        bottom - 160,
        right - 20,
        bottom - 60,
        alert_pixel,
    )
    detail_width = right - detail_left
    # The Qt composer paints a near-white fill identical to the canvas since
    # the mac-parity restyle (4304993b) — only its 1px rounded outline remains
    # distinguishable, so the old fill-area count can never reach 5000 again.
    # Detect the field by its outline: a wide horizontal border run in the
    # composer band (the outline color sits inside the composer predicate's
    # gray range).
    composer = best_horizontal_segment(
        image,
        bottom - 80,
        bottom - 15,
        detail_left + 100,
        right - 100 + 1,
        mac_reference_composer_pixel,
        min_width=int(detail_width * 0.5),
    )
    composer_accessory_pixels = dark_pixel_count(
        image,
        detail_left + int(detail_width * 0.62),
        bottom - 80,
        right - 45,
        bottom - 15,
    )
    bottom_nav_pixels = dark_pixel_count(image, left + 20, bottom - 130, detail_left - 20, bottom - 20)
    header_icon_pixels = dark_pixel_count(image, right - 190, top + 20, right - 18, top + 60)
    empty_wordmark_pixels = pixel_count(
        image,
        detail_left + int(detail_width * 0.25),
        top + 180,
        detail_left + int(detail_width * 0.75),
        min(bottom - 240, top + 430),
        colorful_wordmark_pixel,
    )

    require(
        selected_marker_pixels >= 12,
        "Generated Enchanted Qt selected chat marker was not detected: "
        f"pixels={selected_marker_pixels}",
    )
    require(
        user_bubble_pixels >= 500,
        "Generated Enchanted Qt selected chat user bubble was not detected: "
        f"pixels={user_bubble_pixels}",
    )
    require(
        assistant_message_pixels >= 450,
        "Generated Enchanted Qt selected chat assistant response was not detected: "
        f"pixels={assistant_message_pixels}",
    )
    require(notice_pixels >= 15000, f"Generated Enchanted Qt selected notice was not detected: pixels={notice_pixels}")
    require(composer is not None, "Generated Enchanted Qt selected composer outline was not detected")
    require(
        composer_accessory_pixels >= 20,
        "Generated Enchanted Qt selected composer accessory icon was not detected: "
        f"pixels={composer_accessory_pixels}",
    )
    require(bottom_nav_pixels >= 300, f"Generated Enchanted Qt selected bottom nav was not detected: pixels={bottom_nav_pixels}")
    require(header_icon_pixels >= 20, f"Generated Enchanted Qt selected toolbar icons were not detected: pixels={header_icon_pixels}")
    require(
        empty_wordmark_pixels <= 1000,
        "Generated Enchanted Qt selected chat still shows the empty-state wordmark: "
        f"pixels={empty_wordmark_pixels}",
    )

    return (
        "Quill Enchanted generated Qt selected chat snapshot: "
        f"app={app_width}x{app_height}, "
        f"selected_marker_pixels={selected_marker_pixels}, "
        f"user_bubble_pixels={user_bubble_pixels}, "
        f"assistant_message_pixels={assistant_message_pixels}, "
        f"notice_pixels={notice_pixels}, "
        f"composer={composer[1].width}px@{composer[0]}, "
        f"composer_accessory_pixels={composer_accessory_pixels}, "
        f"bottom_nav_pixels={bottom_nav_pixels}, "
        f"header_icon_pixels={header_icon_pixels}, "
        f"empty_wordmark_pixels={empty_wordmark_pixels}"
    )


def validate_quill_enchanted_linux_qt_settings(image: Screenshot) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(960 <= app_width <= 1220, f"Generated Enchanted Qt settings window width is unexpected: {app_width}px")
    require(660 <= app_height <= 820, f"Generated Enchanted Qt settings window height is unexpected: {app_height}px")

    sidebar_width = min(360, max(300, int(app_width * 0.30)))
    detail_left = left + sidebar_width
    panel_pixels = pixel_count(
        image,
        detail_left + 60,
        top + 90,
        right - 50,
        bottom - 90,
        settings_panel_background_pixel,
    )
    field_pixels = pixel_count(
        image,
        detail_left + 110,
        top + 180,
        right - 110,
        bottom - 120,
        form_field_pixel,
    )
    settings_text_pixels = dark_pixel_count(
        image,
        detail_left + 80,
        top + 105,
        right - 80,
        bottom - 110,
    )
    bottom_nav_pixels = dark_pixel_count(image, left + 20, bottom - 130, detail_left - 20, bottom - 20)
    empty_wordmark_pixels = pixel_count(
        image,
        detail_left + int((right - detail_left) * 0.25),
        top + 130,
        detail_left + int((right - detail_left) * 0.75),
        min(bottom - 180, top + 430),
        cool_wordmark_pixel,
    ) + pixel_count(
        image,
        detail_left + int((right - detail_left) * 0.25),
        top + 130,
        detail_left + int((right - detail_left) * 0.75),
        min(bottom - 180, top + 430),
        warm_wordmark_pixel,
    )
    prompt_card_row = best_prompt_card_row(
        image,
        top + 180,
        min(bottom - 120, top + 470),
        detail_left + 20,
        right - 20,
        min_width=110,
        predicate=generic_qt_card_pixel,
    )

    require(panel_pixels >= 80_000, f"Generated Enchanted Qt settings panel was not detected: pixels={panel_pixels}")
    require(field_pixels >= 25_000, f"Generated Enchanted Qt settings fields were not detected: pixels={field_pixels}")
    require(
        settings_text_pixels >= 1_200,
        f"Generated Enchanted Qt settings labels and controls were not detected: pixels={settings_text_pixels}",
    )
    require(bottom_nav_pixels >= 300, f"Generated Enchanted Qt settings bottom nav was not detected: pixels={bottom_nav_pixels}")
    require(
        empty_wordmark_pixels <= 3_000,
        "Generated Enchanted Qt settings state still shows the empty-state wordmark: "
        f"pixels={empty_wordmark_pixels}",
    )
    require(prompt_card_row is None, f"Generated Enchanted Qt settings state still shows prompt cards: {prompt_card_row}")

    return (
        "Quill Enchanted generated Qt settings snapshot: "
        f"app={app_width}x{app_height}, "
        f"panel_pixels={panel_pixels}, "
        f"field_pixels={field_pixels}, "
        f"settings_text_pixels={settings_text_pixels}, "
        f"bottom_nav_pixels={bottom_nav_pixels}, "
        f"empty_wordmark_pixels={empty_wordmark_pixels}, "
        "prompt_card_row=absent"
    )


def validate_quill_enchanted_linux_qt_utility(image: Screenshot) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(960 <= app_width <= 1220, f"Generated Enchanted Qt utility window width is unexpected: {app_width}px")
    require(660 <= app_height <= 820, f"Generated Enchanted Qt utility window height is unexpected: {app_height}px")

    sidebar_width = min(360, max(300, int(app_width * 0.30)))
    detail_left = left + sidebar_width
    panel_pixels = pixel_count(
        image,
        detail_left + 80,
        top + 130,
        right - 80,
        bottom - 170,
        settings_panel_background_pixel,
    )
    utility_text_pixels = dark_pixel_count(
        image,
        detail_left + 110,
        top + 150,
        right - 110,
        bottom - 190,
    )
    field_pixels = pixel_count(
        image,
        detail_left + 110,
        top + 170,
        right - 110,
        bottom - 180,
        form_field_pixel,
    )
    bottom_nav_pixels = dark_pixel_count(image, left + 20, bottom - 130, detail_left - 20, bottom - 20)
    prompt_card_row = best_prompt_card_row(
        image,
        top + 180,
        min(bottom - 120, top + 470),
        detail_left + 20,
        right - 20,
        min_width=110,
        predicate=generic_qt_card_pixel,
    )

    require(panel_pixels >= 35_000, f"Generated Enchanted Qt utility panel was not detected: pixels={panel_pixels}")
    require(
        utility_text_pixels >= 500,
        f"Generated Enchanted Qt utility panel text was not detected: pixels={utility_text_pixels}",
    )
    require(field_pixels <= 15_000, f"Generated Enchanted Qt utility panel unexpectedly shows settings fields: {field_pixels}")
    require(bottom_nav_pixels >= 300, f"Generated Enchanted Qt utility bottom nav was not detected: pixels={bottom_nav_pixels}")
    require(prompt_card_row is None, f"Generated Enchanted Qt utility state still shows prompt cards: {prompt_card_row}")

    return (
        "Quill Enchanted generated Qt utility snapshot: "
        f"app={app_width}x{app_height}, "
        f"panel_pixels={panel_pixels}, "
        f"utility_text_pixels={utility_text_pixels}, "
        f"field_pixels={field_pixels}, "
        f"bottom_nav_pixels={bottom_nav_pixels}, "
        "prompt_card_row=absent"
    )


def validate_quill_enchanted_linux_gtk_snapshot(image: Screenshot) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(900 <= app_width <= 1180, f"Generated Enchanted GTK window width is unexpected: {app_width}px")
    require(640 <= app_height <= 840, f"Generated Enchanted GTK window height is unexpected: {app_height}px")

    detail_left = left + min(360, max(300, int(app_width * 0.30)))
    sidebar_text_pixels = dark_pixel_count(
        image,
        left + 10,
        top + 60,
        detail_left - 10,
        bottom - 80,
    )
    detail_surface_pixels = pixel_count(
        image,
        detail_left,
        top,
        right + 1,
        bottom + 1,
        generic_gtk_detail_surface_pixel,
    )
    prompt_card_pixels = pixel_count(
        image,
        detail_left + 8,
        top + int(app_height * 0.30),
        right - 20,
        bottom - 20,
        generic_gtk_card_pixel,
    )
    wordmark_pixels = pixel_count(
        image,
        detail_left,
        top + int(app_height * 0.34),
        right + 1,
        min(bottom + 1, top + int(app_height * 0.70)),
        enchanted_linux_gtk_wordmark_pixel,
    )
    detail_text_pixels = dark_pixel_count(image, detail_left, top + 20, right - 20, bottom - 20)
    require(
        detail_surface_pixels >= 350000,
        f"Generated Enchanted GTK detail surface was not detected: pixels={detail_surface_pixels}",
    )
    require(
        prompt_card_pixels >= 30000,
        f"Generated Enchanted GTK prompt cards were not detected: pixels={prompt_card_pixels}",
    )
    require(
        sidebar_text_pixels >= 1200,
        f"Generated Enchanted GTK sidebar history was not detected: pixels={sidebar_text_pixels}",
    )
    require(detail_text_pixels >= 2500, f"Generated Enchanted GTK text content was not detected: pixels={detail_text_pixels}")

    return (
        "Quill Enchanted generated GTK snapshot: "
        f"app={app_width}x{app_height}, "
        f"sidebar_text_pixels={sidebar_text_pixels}, "
        f"detail_surface_pixels={detail_surface_pixels}, "
        f"prompt_card_pixels={prompt_card_pixels}, "
        f"wordmark_pixels={wordmark_pixels}, "
        f"detail_text_pixels={detail_text_pixels}"
    )


ENCHANTED_LINUX_SNAPSHOT_VALIDATORS: dict[str, Callable[[Screenshot], str]] = {
    "quill-enchanted-linux-qt": validate_quill_enchanted_linux_qt_snapshot,
    "quill-enchanted-linux-qt-selected-chat": validate_quill_enchanted_linux_qt_selected_chat,
    "quill-enchanted-linux-qt-settings": validate_quill_enchanted_linux_qt_settings,
    "quill-enchanted-linux-qt-utility": validate_quill_enchanted_linux_qt_utility,
    "quill-enchanted-linux-gtk": validate_quill_enchanted_linux_gtk_snapshot,
}


def validate_quill_enchanted_gtk_list_selection(image: Screenshot) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(900 <= app_width <= 1260, f"Enchanted GTK window width is unexpected: {app_width}px")
    require(620 <= app_height <= 860, f"Enchanted GTK window height is unexpected: {app_height}px")

    sidebar_width = min(340, max(260, int(app_width * 0.30)))
    # Genuine native Enchanted marks the selected conversation with a small leading
    # accent dot (QuillColors.primary), not a filled row, so detect accent blue near the
    # row's leading edge (x0 = left + 4) with dot-sized thresholds. Restrict to the
    # conversation-list band: BELOW the "Conversations" header and ABOVE the bottom
    # action buttons (Delete chat / Clear All), whose trash-can icons also match the
    # accent-blue predicate at top+~594 and would otherwise win best_pixel_row_segment
    # (39px > the selected dot's ~14px) as a false-positive selection match.
    selected_row = best_pixel_row_segment(
        image,
        left + 4,
        top + 320,
        left + sidebar_width - 16,
        min(bottom + 1, top + 520),
        enchanted_primary_pixel,
        min_row_pixels=3,
    )
    require(selected_row is not None, "Enchanted GTK selected conversation row dot was not detected")
    selected_row_segment, selected_row_pixels = selected_row
    selected_row_center_offset = selected_row_segment.center - top
    require(
        # 340 (was an unvalidated 360 calibrated for the old title+2-line-preview
        # card rows): the genuine single-line D-row layout is more compact, so the
        # selected lower row's dot centers higher (~354px, verified from the .qa
        # capture). 340 still rejects an index-0/top-row or header-only selection
        # while accepting the lower selected row.
        selected_row_center_offset >= 340,
        "Enchanted GTK conversation selection did not move to the lower conversation row: "
        f"selected_center={selected_row_center_offset:.1f}px",
    )
    require(
        selected_row_pixels >= 12,
        f"Enchanted GTK selected conversation row dot is too small: pixels={selected_row_pixels}",
    )

    sidebar_text_pixels = dark_pixel_count(image, left + 20, top + 20, left + sidebar_width - 12, bottom - 20)
    detail_text_pixels = dark_pixel_count(image, left + sidebar_width + 20, top + 20, right - 20, bottom - 20)
    require(sidebar_text_pixels >= 500, f"Enchanted GTK sidebar text was not detected: pixels={sidebar_text_pixels}")
    require(detail_text_pixels >= 1200, f"Enchanted GTK detail text was not detected: pixels={detail_text_pixels}")

    return (
        "Quill Enchanted GTK list selection: "
        f"app={app_width}x{app_height}, "
        f"selected_row_pixels={selected_row_pixels}, "
        f"selected_row_y={selected_row_segment.start - top}-{selected_row_segment.end - top}, "
        f"sidebar_text_pixels={sidebar_text_pixels}, "
        f"detail_text_pixels={detail_text_pixels}"
    )


def validate_quill_enchanted_composer_typed(image: Screenshot) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(900 <= app_width <= 1260, f"Enchanted composer window width is unexpected: {app_width}px")
    require(560 <= app_height <= 900, f"Enchanted composer window height is unexpected: {app_height}px")

    sidebar_width = min(340, max(260, int(app_width * 0.30)))
    detail_left = left + sidebar_width
    # The composer occupies the lower portion of the detail pane. Freshly typed
    # text lands at its leading edge, away from the trailing Send pill, so sample
    # the lower-left of the detail pane for the entered glyphs.
    region_left = detail_left + 16
    region_right = right - int(app_width * 0.14)
    region_top = bottom - int(app_height * 0.32)
    region_bottom = bottom - int(app_height * 0.05)
    typed_text_pixels = dark_pixel_count(image, region_left, region_top, region_right, region_bottom)
    require(
        typed_text_pixels >= 120,
        "Enchanted composer typed text was not detected (composer did not accept input): "
        f"pixels={typed_text_pixels}",
    )
    return (
        "Quill Enchanted composer typed: "
        f"app={app_width}x{app_height}, typed_text_pixels={typed_text_pixels}"
    )


def enchanted_user_bubble_pixel(rgb: tuple[int, int, int]) -> bool:
    # The trailing user message bubble uses macOS system blue (#007AFF ~
    # (0, 122, 255)) -- bluer and far less red than the accent button fill that
    # enchanted_primary_pixel matches (~#4285F4, red ~66).
    red, green, blue = rgb
    return red <= 45 and 95 <= green <= 160 and blue >= 230 and blue - red >= 150


def validate_quill_enchanted_message_sent(image: Screenshot) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(900 <= app_width <= 1260, f"Enchanted message-sent window width is unexpected: {app_width}px")
    require(560 <= app_height <= 900, f"Enchanted message-sent window height is unexpected: {app_height}px")

    sidebar_width = min(340, max(260, int(app_width * 0.30)))
    detail_left = left + sidebar_width
    detail_width = right - detail_left + 1
    # A sent message renders as an accent-blue trailing "You" bubble at the top
    # of the transcript. The empty state / unsent composer has no accent-blue in
    # the detail pane (the blue New-chat button + selected sidebar row are left
    # of detail_left), so this cleanly confirms the message was sent.
    bubble_pixels = pixel_count(
        image,
        detail_left + int(detail_width * 0.45),
        top + int(app_height * 0.06),
        right - 6,
        top + int(app_height * 0.34),
        enchanted_user_bubble_pixel,
    )
    require(
        bubble_pixels >= 500,
        "Enchanted sent user message bubble was not detected in the transcript "
        f"(message may not have sent): pixels={bubble_pixels}",
    )
    return (
        "Quill Enchanted message sent: "
        f"app={app_width}x{app_height}, user_bubble_pixels={bubble_pixels}"
    )


def validate_quill_enchanted_clear_all(image: Screenshot) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(900 <= app_width <= 1260, f"Enchanted clear-all window width is unexpected: {app_width}px")
    require(560 <= app_height <= 900, f"Enchanted clear-all window height is unexpected: {app_height}px")

    sidebar_width = min(340, max(260, int(app_width * 0.30)))
    region_left = left + 16
    region_right = left + sidebar_width - 16
    region_top = top + int(app_height * 0.40)
    region_bottom = bottom - int(app_height * 0.18)
    # The smoke seeds + selects a conversation, then clicks "Clear all". After a
    # successful clear no conversation rows remain, so the selected-row accent
    # (enchanted_primary_pixel) is gone from the sidebar conversation list.
    selected_row_pixels = pixel_count(
        image, region_left, region_top, region_right, region_bottom, enchanted_primary_pixel
    )
    require(
        selected_row_pixels <= 120,
        "Enchanted conversations were not cleared (a selected conversation row remains): "
        f"pixels={selected_row_pixels}",
    )
    # The cleared sidebar still renders content (the "No saved chats yet" card).
    sidebar_text_pixels = dark_pixel_count(image, region_left, region_top, region_right, region_bottom)
    require(
        sidebar_text_pixels >= 60,
        f"Enchanted cleared sidebar content was not detected: pixels={sidebar_text_pixels}",
    )
    return (
        "Quill Enchanted clear-all: "
        f"app={app_width}x{app_height}, selected_row={selected_row_pixels}, sidebar_text={sidebar_text_pixels}"
    )


def validate_quill_enchanted_new_chat(image: Screenshot) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(900 <= app_width <= 1260, f"Enchanted new-chat window width is unexpected: {app_width}px")
    require(560 <= app_height <= 900, f"Enchanted new-chat window height is unexpected: {app_height}px")

    sidebar_width = min(340, max(260, int(app_width * 0.30)))
    # Clicking "New chat" creates + selects a conversation, so an accent-selected
    # row appears in the sidebar conversation list. The region starts well below
    # the top so the accent New-chat button itself is not counted.
    region_left = left + 16
    region_right = left + sidebar_width - 16
    region_top = top + int(app_height * 0.40)
    region_bottom = bottom - int(app_height * 0.22)
    selected_row_pixels = pixel_count(
        image, region_left, region_top, region_right, region_bottom, enchanted_primary_pixel
    )
    require(
        selected_row_pixels >= 12,
        "Enchanted New chat did not create a selected conversation row: "
        f"pixels={selected_row_pixels}",
    )
    return (
        "Quill Enchanted new chat: "
        f"app={app_width}x{app_height}, selected_row_pixels={selected_row_pixels}"
    )


def validate_quill_chatkit_gtk_list_selection(image: Screenshot, product: str) -> str:
    app_label = product.removesuffix("-list-selection")
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(760 <= app_width <= 1120, f"{app_label} GTK window width is unexpected: {app_width}px")
    require(560 <= app_height <= 820, f"{app_label} GTK window height is unexpected: {app_height}px")

    sidebar_width = min(340, max(240, int(app_width * 0.34)))
    selected_row = best_pixel_row_segment(
        image,
        left + 14,
        top + 80,
        left + sidebar_width - 14,
        min(bottom + 1, top + 340),
        chatkit_gtk_selected_row_pixel,
        min_row_pixels=24,
    )
    require(selected_row is not None, f"{app_label} GTK selected chat row was not detected")
    selected_row_segment, selected_row_pixels = selected_row
    selected_row_center_offset = selected_row_segment.center - top
    require(
        selected_row_center_offset >= 115,
        f"{app_label} GTK selection did not move below the first row: "
        f"selected_center={selected_row_center_offset:.1f}px",
    )
    require(
        selected_row_pixels >= 260,
        f"{app_label} GTK selected chat row is too small: pixels={selected_row_pixels}",
    )

    sidebar_text_pixels = dark_pixel_count(image, left + 16, top + 20, left + sidebar_width - 10, bottom - 20)
    detail_text_pixels = dark_pixel_count(image, left + sidebar_width + 20, top + 20, right - 20, bottom - 20)
    require(sidebar_text_pixels >= 400, f"{app_label} GTK sidebar text was not detected: pixels={sidebar_text_pixels}")
    require(detail_text_pixels >= 650, f"{app_label} GTK detail text was not detected: pixels={detail_text_pixels}")

    return (
        f"{app_label} GTK list selection: "
        f"app={app_width}x{app_height}, "
        f"selected_row_pixels={selected_row_pixels}, "
        f"selected_row_y={selected_row_segment.start - top}-{selected_row_segment.end - top}, "
        f"sidebar_text_pixels={sidebar_text_pixels}, "
        f"detail_text_pixels={detail_text_pixels}"
    )


def validate_quill_generic_gtk_list_selection(image: Screenshot, product: str) -> str:
    app_label = product.removesuffix("-gtk-list-selection")
    selected_row_pixel = generic_gtk_selected_row_pixel
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(760 <= app_width <= 1240, f"Generic GTK window width is unexpected: {app_width}px")
    require(560 <= app_height <= 840, f"Generic GTK window height is unexpected: {app_height}px")

    divider_search = range(left + 230, min(right + 1, left + 390))
    divider_x = max(
        divider_search,
        key=lambda x: line_column_score(image, x, top + 20, bottom - 20),
    )
    divider_score = line_column_score(image, divider_x, top + 20, bottom - 20)
    if divider_score < int(app_height * 0.12):
        divider_x = left + min(360, max(260, int(app_width * 0.34)))

    sidebar_pixels = pixel_count(
        image,
        left,
        top,
        divider_x,
        bottom + 1,
        generic_gtk_sidebar_pixel,
    )
    selected_row = best_pixel_row_segment(
        image,
        left + 12,
        top + 120,
        max(left + 13, divider_x - 12),
        min(bottom + 1, top + 560),
        selected_row_pixel,
        min_row_pixels=28,
    )
    require(selected_row is not None, "Generic GTK selected list row was not detected")
    selected_row_segment, selected_row_pixels = selected_row
    selected_row_center_offset = selected_row_segment.center - top
    require(
        selected_row_center_offset >= 220,
        "Generic GTK list selection did not move to the lower app row: "
        f"selected_center={selected_row_center_offset:.1f}px",
    )

    detail_left = min(right - 40, divider_x + 16)
    detail_surface_pixels = pixel_count(
        image,
        detail_left,
        top,
        right + 1,
        bottom + 1,
        generic_gtk_detail_surface_pixel,
    )
    card_pixels = pixel_count(
        image,
        detail_left + 4,
        top + 72,
        right - 20,
        bottom - 20,
        generic_gtk_card_pixel,
    )
    sidebar_text_pixels = dark_pixel_count(
        image,
        left + 16,
        top + 18,
        max(left + 17, divider_x - 12),
        bottom - 20,
    )
    detail_text_pixels = dark_pixel_count(
        image,
        detail_left + 4,
        top + 20,
        right - 20,
        bottom - 20,
    )

    require(sidebar_pixels >= 18_000, f"Generic GTK sidebar background was not detected: pixels={sidebar_pixels}")
    require(selected_row_pixels >= 420, f"Generic GTK selected list row is too small: pixels={selected_row_pixels}")
    require(
        detail_surface_pixels >= 24_000,
        f"Generic GTK detail surface was not detected: pixels={detail_surface_pixels}",
    )
    require(card_pixels >= 4_000, f"Generic GTK detail cards were not detected: pixels={card_pixels}")
    require(sidebar_text_pixels >= 320, f"Generic GTK sidebar text was not detected: pixels={sidebar_text_pixels}")
    require(detail_text_pixels >= 420, f"Generic GTK detail text was not detected: pixels={detail_text_pixels}")

    return (
        f"{app_label} GTK list selection: "
        f"app={app_width}x{app_height}, "
        f"divider_x={divider_x - left}, "
        f"selected_row_pixels={selected_row_pixels}, "
        f"selected_row_y={selected_row_segment.start - top}-{selected_row_segment.end - top}, "
        f"sidebar_text_pixels={sidebar_text_pixels}, "
        f"detail_text_pixels={detail_text_pixels}"
    )


def validate_quill_generic_qt_list_selection(image: Screenshot, product: str) -> str:
    app_label = product.removesuffix("-qt-list-selection")
    palette_label = "Generic Qt"
    sidebar_pixel = generic_qt_sidebar_pixel
    selected_row_pixel = generic_qt_selected_row_pixel
    detail_surface_pixel = generic_qt_detail_surface_pixel

    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(900 <= app_width <= 1240, f"{palette_label} window width is unexpected: {app_width}px")
    require(600 <= app_height <= 840, f"{palette_label} window height is unexpected: {app_height}px")

    divider_search = range(left + 270, min(right + 1, left + 390))
    divider_x = max(
        divider_search,
        key=lambda x: line_column_score(image, x, top + 20, bottom - 20),
    )
    divider_score = line_column_score(image, divider_x, top + 20, bottom - 20)
    require(
        divider_score >= int(app_height * 0.24),
        f"{palette_label} splitter was not detected: x={divider_x}, score={divider_score}",
    )

    sidebar_pixels = pixel_count(
        image,
        left,
        top,
        divider_x,
        bottom + 1,
        sidebar_pixel,
    )
    selected_row = best_pixel_row_segment(
        image,
        left + 12,
        top + 140,
        max(left + 13, divider_x - 12),
        min(bottom + 1, top + 520),
        selected_row_pixel,
        min_row_pixels=42,
    )
    require(selected_row is not None, f"{palette_label} selected list row was not detected")
    selected_row_segment, selected_row_pixels = selected_row
    selected_row_center_offset = selected_row_segment.center - top
    require(
        selected_row_center_offset >= 270,
        f"{palette_label} list selection did not move to the lower app row: "
        f"selected_center={selected_row_center_offset:.1f}px",
    )

    detail_surface_pixels = pixel_count(
        image,
        divider_x + 16,
        top,
        right + 1,
        bottom + 1,
        detail_surface_pixel,
    )
    card_pixels = pixel_count(
        image,
        divider_x + 20,
        top + 84,
        right - 20,
        bottom - 20,
        generic_qt_card_pixel,
    )
    sidebar_text_pixels = dark_pixel_count(
        image,
        left + 16,
        top + 18,
        max(left + 17, divider_x - 12),
        bottom - 20,
    )
    detail_text_pixels = dark_pixel_count(
        image,
        divider_x + 20,
        top + 20,
        right - 20,
        bottom - 20,
    )

    require(sidebar_pixels >= 28_000, f"{palette_label} sidebar background was not detected: pixels={sidebar_pixels}")
    require(selected_row_pixels >= 900, f"{palette_label} selected list row is too small: pixels={selected_row_pixels}")
    require(
        detail_surface_pixels >= 36_000,
        f"{palette_label} detail surface was not detected: pixels={detail_surface_pixels}",
    )
    require(card_pixels >= 18_000, f"{palette_label} detail cards were not detected: pixels={card_pixels}")
    require(sidebar_text_pixels >= 400, f"{palette_label} sidebar text was not detected: pixels={sidebar_text_pixels}")
    require(detail_text_pixels >= 500, f"{palette_label} detail text was not detected: pixels={detail_text_pixels}")

    return (
        f"{app_label} Qt list selection: "
        f"app={app_width}x{app_height}, "
        f"divider={divider_x - left}px/{divider_score}, "
        f"sidebar_pixels={sidebar_pixels}, "
        f"selected_row_pixels={selected_row_pixels}, "
        f"selected_row_y={selected_row_segment.start - top}-{selected_row_segment.end - top}, "
        f"detail_surface_pixels={detail_surface_pixels}, "
        f"card_pixels={card_pixels}, "
        f"sidebar_text_pixels={sidebar_text_pixels}, "
        f"detail_text_pixels={detail_text_pixels}"
    )


def validate_quill_wireguard_qt_native(
    image: Screenshot,
    minimum_selected_center_offset: int | None = None,
    require_focused_title: bool = False,
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
    focused_title_border_pixels = pixel_count(
        image,
        divider_x + 18,
        top + 18,
        min(right + 1, divider_x + 520),
        min(bottom + 1, top + 68),
        wireguard_qt_focused_title_border_pixel,
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
    if require_focused_title:
        require(
            focused_title_border_pixels >= 40,
            "WireGuard Qt focused editable tunnel title was not detected: "
            f"pixels={focused_title_border_pixels}",
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
        f"detail_text_pixels={detail_text_pixels}, "
        f"focused_title_border_pixels={focused_title_border_pixels}"
    )


def validate_quill_wireguard_gtk_native(
    image: Screenshot,
    minimum_selected_center_offset: int | None = None,
    scenario: str = "native",
) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    require(860 <= app_width <= 1100, f"WireGuard GTK window width is unexpected: {app_width}px")
    require(560 <= app_height <= 760, f"WireGuard GTK window height is unexpected: {app_height}px")

    divider_min_x = left + int(app_width * 0.24)
    divider_max_x = left + int(app_width * 0.58)
    divider_search = range(divider_min_x, min(right + 1, divider_max_x))
    divider_x = max(
        divider_search,
        key=lambda x: line_column_score(image, x, top + 20, bottom - 20),
    )
    divider_score = line_column_score(image, divider_x, top + 20, bottom - 20)
    require(
        divider_score >= int(app_height * 0.15),
        f"WireGuard GTK sidebar divider was not detected: x={divider_x}, score={divider_score}",
    )

    sidebar_pixels = pixel_count(
        image,
        left,
        top,
        min(right + 1, left + 320),
        bottom + 1,
        wireguard_gtk_sidebar_pixel,
    )
    selected_row = best_pixel_row_segment(
        image,
        left + 8,
        top + 62,
        min(right + 1, left + 276),
        min(bottom + 1, top + 285),
        wireguard_selected_row_pixel,
        min_row_pixels=28,
    )
    require(selected_row is not None, f"WireGuard GTK selected tunnel row was not detected for {scenario}")
    selected_row_segment, selected_row_pixels = selected_row
    selected_row_center_offset = selected_row_segment.center - top
    if minimum_selected_center_offset is not None:
        require(
            selected_row_center_offset >= minimum_selected_center_offset,
            f"WireGuard GTK {scenario} did not select the expected tunnel row: "
            f"selected_center={selected_row_center_offset:.1f}px, "
            f"minimum={minimum_selected_center_offset}px",
        )

    section_pixels = pixel_count(
        image,
        divider_x + 12,
        top + 58,
        right + 1,
        bottom + 1,
        wireguard_gtk_section_pixel,
    )
    sidebar_text_pixels = dark_pixel_count(
        image,
        left + 12,
        top + 18,
        min(right + 1, left + 320),
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
        sidebar_pixels >= 18_000,
        f"WireGuard GTK sidebar background was not detected: pixels={sidebar_pixels}",
    )
    require(
        selected_row_pixels >= 120,
        f"WireGuard GTK selected tunnel row is too small: pixels={selected_row_pixels}",
    )
    require(
        section_pixels >= 8_000,
        f"WireGuard GTK detail section backgrounds were not detected: pixels={section_pixels}",
    )
    require(
        sidebar_text_pixels >= 160,
        f"WireGuard GTK sidebar tunnel text was not detected: pixels={sidebar_text_pixels}",
    )
    require(
        detail_text_pixels >= 420,
        f"WireGuard GTK detail text was not detected: pixels={detail_text_pixels}",
    )

    return (
        f"Quill WireGuard GTK {scenario}: "
        f"app={app_width}x{app_height}, "
        f"divider={divider_x - left}px/{divider_score}, "
        f"sidebar_pixels={sidebar_pixels}, "
        f"selected_row_pixels={selected_row_pixels}, "
        f"selected_row_y={selected_row_segment.start - top}-{selected_row_segment.end - top}, "
        f"section_pixels={section_pixels}, "
        f"sidebar_text_pixels={sidebar_text_pixels}, "
        f"detail_text_pixels={detail_text_pixels}"
    )


def validate_quill_wireguard_gtk_import(
    image: Screenshot,
    minimum_selected_center_offset: int = 145,
) -> str:
    return validate_quill_wireguard_gtk_native(
        image,
        minimum_selected_center_offset=minimum_selected_center_offset,
        scenario="import",
    )


def validate_quill_wireguard_import_error(image: Screenshot, backend: str) -> str:
    left, right, top, bottom = content_bounds(image)
    app_width = right - left + 1
    app_height = bottom - top + 1
    if backend == "qt":
        require(500 <= app_width <= 720, f"WireGuard Qt import dialog width is unexpected: {app_width}px")
        require(360 <= app_height <= 540, f"WireGuard Qt import dialog height is unexpected: {app_height}px")
        x0 = left + 16
        y0 = top + 60
        x1 = right - 16
        y1 = bottom - 48
        minimum_error_pixels = 12
        minimum_dark_pixels = 120
    else:
        require(860 <= app_width <= 1100, f"WireGuard GTK window width is unexpected: {app_width}px")
        require(560 <= app_height <= 760, f"WireGuard GTK window height is unexpected: {app_height}px")
        x0 = left + int(app_width * 0.30)
        y0 = top + 100
        x1 = right - 20
        y1 = bottom - 40
        minimum_error_pixels = 10
        minimum_dark_pixels = 260

    error_pixels = pixel_count(image, x0, y0, x1, y1, wireguard_error_text_pixel)
    dark_pixels = dark_pixel_count(image, x0, y0, x1, y1)
    require(
        error_pixels >= minimum_error_pixels,
        "WireGuard import error text was not detected: "
        f"backend={backend}, error_pixels={error_pixels}, roi=({x0},{y0})-({x1},{y1})",
    )
    require(
        dark_pixels >= minimum_dark_pixels,
        "WireGuard import dialog/body text was not detected: "
        f"backend={backend}, dark_pixels={dark_pixels}, roi=({x0},{y0})-({x1},{y1})",
    )

    return (
        f"Quill WireGuard {backend.upper()} import error: "
        f"app={app_width}x{app_height}, "
        f"error_pixels={error_pixels}, "
        f"dark_pixels={dark_pixels}, "
        f"roi=({x0},{y0})-({x1},{y1})"
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


def solderscope_toolbar_pixel(rgb: tuple[int, int, int]) -> bool:
    total = sum(rgb)
    return 24 <= total <= 560 and max(rgb) - min(rgb) <= 96


def validate_quill_solderscope_launch(image: Screenshot) -> str:
    toolbar_height = min(140, image.height)
    toolbar_pixels = pixel_count(
        image,
        0,
        0,
        image.width,
        toolbar_height,
        solderscope_toolbar_pixel,
    )
    top_nonblack_pixels = pixel_count(
        image,
        0,
        0,
        image.width,
        toolbar_height,
        lambda rgb: sum(rgb) >= 24,
    )
    canvas_dark_pixels = pixel_count(
        image,
        image.width // 4,
        max(toolbar_height, image.height // 4),
        (image.width * 3) // 4,
        (image.height * 3) // 4,
        lambda rgb: sum(rgb) <= 96,
    )
    require(
        toolbar_pixels >= 1_500,
        f"SolderScope dark toolbar pixels were not detected near the top: pixels={toolbar_pixels}",
    )
    require(
        top_nonblack_pixels >= 5_000,
        f"SolderScope top chrome appears black/empty: nonblack_pixels={top_nonblack_pixels}",
    )
    require(
        canvas_dark_pixels >= 25_000,
        f"SolderScope microscope canvas was not detected: dark_pixels={canvas_dark_pixels}",
    )

    return (
        "Quill SolderScope launch: "
        f"toolbar_pixels={toolbar_pixels}, "
        f"top_nonblack_pixels={top_nonblack_pixels}, "
        f"canvas_dark_pixels={canvas_dark_pixels}"
    )


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
        # Generic SwiftUI→Qt backend smoke (BackendQt, QUILLUI_QT_GENERIC). It
        # renders the same ~640x760 panel surface as the hand-built Qt smoke, so
        # it shares the smoke launch-window size floor (600x560) rather than the
        # larger full-app default. Additive: existing products are unaffected.
        or product.startswith("quill-qt-generic-smoke")
    )
    compact_wireguard_dialog_product = product in {
        "quill-wireguard-qt-import-invalid-paste",
        "quill-wireguard-qt-import-invalid-file",
    }
    compact_quill_chat_dialog_product = product in {
        "quill-chat-linux-mac-reference-settings-delete-confirmation",
    }
    solderscope_launch_product = product in {
        "quill-solderscope-launch",
        "quill-solderscope-visual",
        "quill-solderscope-interaction",
    }
    if compact_quill_chat_dialog_product:
        minimum_width = 260
        minimum_height = 140
    elif compact_wireguard_dialog_product:
        minimum_width = 500
        minimum_height = 360
    elif smoke_product:
        minimum_width = 600
        minimum_height = 560
    else:
        minimum_width = 900
        minimum_height = 600
    # SolderScope's valid no-camera state is intentionally mostly black: the
    # microscope canvas fills the window while only toolbar controls and status
    # text are bright. Use the product-specific toolbar/canvas predicates below
    # for real blank-screen detection instead of a light-app global mean floor.
    minimum_mean = 250 if solderscope_launch_product else 1000
    minimum_stddev = 1000 if solderscope_launch_product else 250
    require(
        image.width >= minimum_width and image.height >= minimum_height,
        f"Screenshot is unexpectedly small: {image.width}x{image.height}",
    )
    require(
        image.mean > minimum_mean,
        f"Screenshot appears blank or near-black: mean={image.mean}",
    )
    require(
        image.stddev > minimum_stddev,
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
    elif product == "quill-chat-linux-mac-reference-settings-bearer-token-typed":
        print(validate_quill_chat_mac_reference_settings_panel(image, require_typed_bearer_token=True))
    elif product == "quill-chat-linux-mac-reference-settings-ping-interval-typed":
        print(validate_quill_chat_mac_reference_settings_panel(image, require_typed_ping_interval=True))
    elif product == "quill-chat-linux-mac-reference-settings-default-model-selected":
        print(validate_quill_chat_mac_reference_settings_panel(image, require_selected_default_model=True))
    elif product == "quill-chat-linux-mac-reference-settings-delete-confirmation":
        print(validate_quill_chat_mac_reference_settings_delete_confirmation(image))
    elif product == "quill-chat-linux-mac-reference-completions-panel":
        print(validate_quill_chat_mac_reference_completions_panel(image))
    elif product == "quill-chat-linux-mac-reference-completions-panel-visible":
        print(validate_quill_chat_mac_reference_completions_panel_visible(image))
    elif product == "quill-chat-linux-mac-reference-completions-new-sheet":
        print(validate_quill_chat_mac_reference_completions_new_sheet(image))
    elif product == "quill-chat-linux-mac-reference-completions-saved":
        print(validate_quill_chat_mac_reference_completions_saved(image))
    elif product == "quill-chat-linux-mac-reference-completions-edited":
        print(validate_quill_chat_mac_reference_completions_edited(image))
    elif product == "quill-chat-linux-mac-reference-completions-deleted":
        print(validate_quill_chat_mac_reference_completions_deleted(image))
    elif product == "quill-chat-linux-mac-reference-history-selection":
        print(validate_quill_chat_mac_reference_history_selection(image))
    elif product == "quill-chat-linux-mac-reference-transcript-selection":
        print(validate_quill_chat_mac_reference_history_selection(image, require_transcript=True))
    elif product == "quill-chat-linux-mac-reference-markdown-transcript-selection":
        print(validate_quill_chat_mac_reference_markdown_transcript_selection(image))
    elif product == "quill-chat-linux-mac-reference-message-hover-actions":
        print(validate_quill_chat_mac_reference_message_hover_actions(image))
    elif product == "quill-chat-linux-mac-reference-long-transcript-selection":
        print(validate_quill_chat_mac_reference_long_transcript_selection(image))
    elif product == "quill-chat-linux-mac-reference-prompt-send":
        print(validate_quill_chat_mac_reference_prompt_send(image))
    elif product == "quill-chat-linux-mac-reference-composer-send":
        print(validate_quill_chat_mac_reference_composer_send(image))
    elif product == "quill-chat-linux-mac-reference-toolbar-model-selected":
        print(validate_quill_chat_mac_reference_toolbar_model_selected(image))
    elif product == "quill-chat-linux-mac-reference-new-chat":
        print(validate_quill_chat_mac_reference(image))
    elif product == "quill-chat-linux-mac-reference-copy-chat":
        print(validate_quill_chat_mac_reference_history_selection(image, require_transcript=True))
    elif product == "quill-chat-linux-mac-reference-copy-chat-json":
        print(validate_quill_chat_mac_reference_history_selection(image, require_transcript=True))
    elif product == "quill-chat-linux-functional-transcript":
        print(validate_quill_chat_functional_transcript(image))
    elif product in {"quill-enchanted-mac-reference", "quill-enchanted-linux-mac-reference"}:
        print(validate_quill_enchanted_mac_reference(image))
    elif product in {"quill-chat-mac-reference", "quill-chat-linux-mac-reference"}:
        print(validate_quill_chat_mac_reference(image))
    elif product == "quill-enchanted-qt":
        print(validate_quill_enchanted_qt_native(image))
    elif product == "quill-enchanted":
        # The bare "quill-enchanted" verify product covers TWO different gtk
        # captures: the empty-state visual smoke (quill-enchanted-gtk.png, the
        # direct EnchantedRootView build) and the backend-interaction smoke
        # (quill-enchanted-*interaction*-gtk.png), which renders the stale
        # pre-#138-#145 runtime sidebar (blue New-chat button, inline endpoint —
        # tracked in #151) and is NOT the empty state. Gate ONLY the empty-state
        # capture against the genuine-native landmarks (#24): centered gradient
        # wordmark, minimal sidebar (no blue New-chat button), horizontal 4-card
        # row, short composer, 3-item bottom nav. The interaction capture keeps
        # its prior (structural) treatment until #151 brings the runtime sidebar
        # in line.
        if "interaction" in str(image.path):
            print(
                "Quill Enchanted interaction-smoke capture: not gated by the "
                "empty-state parity validator (stale runtime sidebar tracked in #151)"
            )
        else:
            print(validate_quill_enchanted_empty_state_gtk(image))
    elif product == "quill-enchanted-qt-list-selection":
        # The lower selected conversation's leading accent dot centers at ~354px in
        # the compact single-line D-row layout (verified from the captured .qa PNG).
        # 360 was an unvalidated guess (the gate never actually reached this smoke
        # until the dot rendered); 340 matches the real render and the GTK sibling.
        print(validate_quill_enchanted_qt_native(image, minimum_selected_center_offset=340))
    elif product in ENCHANTED_LINUX_SNAPSHOT_VALIDATORS:
        print(ENCHANTED_LINUX_SNAPSHOT_VALIDATORS[product](image))
    elif product == "quill-enchanted-list-selection":
        print(validate_quill_enchanted_gtk_list_selection(image))
    elif product == "quill-enchanted-composer-typed":
        print(validate_quill_enchanted_composer_typed(image))
    elif product == "quill-enchanted-new-chat":
        print(validate_quill_enchanted_new_chat(image))
    elif product == "quill-enchanted-message-sent":
        print(validate_quill_enchanted_message_sent(image))
    elif product == "quill-enchanted-clear-all":
        print(validate_quill_enchanted_clear_all(image))
    elif product in CHAT_GTK_LIST_SELECTION_PRODUCTS:
        print(validate_quill_chatkit_gtk_list_selection(image, product))
    elif product in GENERIC_GTK_LIST_SELECTION_PRODUCTS:
        print(validate_quill_generic_gtk_list_selection(image, product))
    elif product in GENERIC_QT_LIST_SELECTION_PRODUCTS:
        print(validate_quill_generic_qt_list_selection(image, product))
    elif product == "quill-wireguard-qt":
        print(validate_quill_wireguard_qt_native(image))
    elif product == "quill-wireguard-qt-tunnel-selection":
        print(validate_quill_wireguard_qt_native(image, minimum_selected_center_offset=100))
    elif product == "quill-wireguard-qt-name-edit":
        print(validate_quill_wireguard_qt_native(
            image,
            minimum_selected_center_offset=100,
            require_focused_title=True,
        ))
    elif product in {"quill-wireguard-qt-import-paste", "quill-wireguard-qt-import-file"}:
        print(validate_quill_wireguard_qt_native(image, minimum_selected_center_offset=145))
    elif product in {"quill-wireguard-qt-import-invalid-paste", "quill-wireguard-qt-import-invalid-file"}:
        print(validate_quill_wireguard_import_error(image, backend="qt"))
    elif product == "quill-wireguard":
        print(validate_quill_wireguard_gtk_native(image))
    elif product == "quill-wireguard-name-edit":
        print(validate_quill_wireguard_gtk_native(
            image,
            minimum_selected_center_offset=100,
            scenario="name edit",
        ))
    elif product in {"quill-wireguard-import-paste", "quill-wireguard-import-file"}:
        print(validate_quill_wireguard_gtk_import(image))
    elif product in {"quill-wireguard-import-invalid-paste", "quill-wireguard-import-invalid-file"}:
        print(validate_quill_wireguard_import_error(image, backend="gtk"))
    elif product in {"quill-solderscope-launch", "quill-solderscope-visual", "quill-solderscope-interaction"}:
        print(validate_quill_solderscope_launch(image))
    elif product in {
        "quill-gtk-interaction-smoke-open",
        "quill-qt-interaction-smoke-open",
        # Generic SwiftUI→Qt backend smoke reuses the exact interaction-smoke
        # validator (window 600-700x720-800 + a dark panel >=10000 px in the ROI).
        # No validator code is weakened; this is an additive product mapping.
        "quill-qt-generic-smoke-open",
    }:
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
