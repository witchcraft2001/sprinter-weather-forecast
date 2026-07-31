#!/usr/bin/env python3
"""Build deterministic weather tiles from editor-friendly PNG sources."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from png_assets import read_sprinter_png, write_indexed_png


PAGE = 16 * 1024
TILE = 16
TRANSPARENT = 0xFF
PAGE_COUNT = 5
PALETTE_PAGE = 4
PALETTE_OFFSET = 0x3D00

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build" / "generated" / "weather_assets"
SOURCE = ROOT / "resources" / "gfx"

WEATHER_ICONS = (
    "00-clear",
    "01-mainly-clear",
    "02-partly-cloudy",
    "03-cloudy",
    "04-fog",
    "05-drizzle",
    "06-freezing-drizzle",
    "07-rain",
    "08-freezing-rain",
    "09-snow",
    "10-snow-grains",
    "11-snow-showers",
    "12-rain-showers",
    "13-thunderstorm",
    "14-unknown",
)

UTILITY_ICONS = ("thermometer", "humidity", "wind", "precipitation")


def palette() -> bytes:
    # Standard EGA-compatible first 16 colours; AFNT320 uses these indexes.
    ega = (
        (0, 0, 0), (0, 0, 170), (0, 170, 0), (0, 170, 170),
        (170, 0, 0), (170, 0, 170), (170, 85, 0), (170, 170, 170),
        (85, 85, 85), (85, 85, 255), (85, 255, 85), (85, 255, 255),
        (255, 85, 85), (255, 85, 255), (255, 255, 85), (255, 255, 255),
    )
    colours = list(ega) + [
        (16, 28, 54), (35, 62, 98), (72, 107, 150), (246, 199, 72),
        (240, 242, 245), (164, 191, 210), (66, 142, 221), (83, 181, 108),
        (115, 190, 235), (206, 230, 247), (118, 78, 47),
    ]
    colours.extend([(0, 0, 0)] * (256 - len(colours)))
    return bytes(component for colour in colours for component in colour)


def canvas(size: int) -> list[list[int]]:
    return [[TRANSPARENT] * size for _ in range(size)]


def px(image: list[list[int]], x: int, y: int, colour: int) -> None:
    if 0 <= y < len(image) and 0 <= x < len(image):
        image[y][x] = colour


def rect(image: list[list[int]], x: int, y: int, w: int, h: int, colour: int) -> None:
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            px(image, xx, yy, colour)


def circle(image: list[list[int]], cx: int, cy: int, radius: int, colour: int) -> None:
    rr = radius * radius
    for y in range(cy - radius, cy + radius + 1):
        for x in range(cx - radius, cx + radius + 1):
            if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= rr:
                px(image, x, y, colour)


def cloud(image: list[list[int]], scale: int) -> None:
    base = 16 * scale
    circle(image, 23 * scale, 29 * scale, 9 * scale, 20)
    circle(image, 34 * scale, 24 * scale, 12 * scale, 20)
    circle(image, 46 * scale, 30 * scale, 9 * scale, 20)
    rect(image, 16 * scale, 30 * scale, 39 * scale, 11 * scale, 20)
    rect(image, 19 * scale, 40 * scale, 33 * scale, 3 * scale, 21)


def sun(image: list[list[int]], scale: int) -> None:
    circle(image, 26 * scale, 25 * scale, 10 * scale, 19)
    for dx, dy in ((0, -17), (0, 17), (-17, 0), (17, 0), (-12, -12), (12, 12), (-12, 12), (12, -12)):
        circle(image, (26 + dx) * scale, (25 + dy) * scale, max(1, 2 * scale), 19)


def weather_icon(kind: int, size: int) -> list[list[int]]:
    # Coordinates below are authored against a 64px grid.  Integer division
    # here silently produced scale 0 for any smaller size, collapsing the whole
    # icon into a few pixels at the origin; smaller variants come from halve().
    if size % 64:
        raise SystemExit(f"weather_icon size {size} must be a multiple of 64")
    scale = size // 64
    image = canvas(size)
    if kind in (0, 1, 2):
        sun(image, scale)
    if kind == 1:
        cloud(image, scale)
    elif kind == 2:
        cloud(image, scale)
    elif kind == 3:
        cloud(image, scale)
    elif kind in (4, 5, 6, 7, 8, 9, 10, 11, 12, 13):
        cloud(image, scale)
    elif kind == 14:
        rect(image, 22 * scale, 20 * scale, 22 * scale, 24 * scale, 17)
        rect(image, 27 * scale, 25 * scale, 12 * scale, 14 * scale, 15)
        return image

    if kind == 4:  # fog
        for row in (45, 51, 57):
            rect(image, 12 * scale, row * scale, 42 * scale, 2 * scale, 21)
    elif kind in (5, 6, 7, 8, 12):
        for x in (23, 34, 45):
            rect(image, x * scale, 46 * scale, 2 * scale, 8 * scale, 22 if kind != 6 else 23)
            px(image, (x - 1) * scale, 54 * scale, 22 if kind != 6 else 23)
    elif kind in (9, 10, 11, 13):
        for x, y in ((23, 48), (35, 52), (46, 48)):
            circle(image, x * scale, y * scale, 3 * scale, 24)
    if kind == 13:
        rect(image, 34 * scale, 41 * scale, 4 * scale, 11 * scale, 15)
        rect(image, 30 * scale, 48 * scale, 8 * scale, 4 * scale, 15)
    return image


def digit_tile(symbol: str) -> bytes:
    data = canvas(16)
    segments = {
        "0": "abcedf", "1": "bc", "2": "abged", "3": "abgcd",
        "4": "fgbc", "5": "afgcd", "6": "afgecd", "7": "abc",
        "8": "abcdefg", "9": "abfgcd",
    }
    positions = {
        "a": (4, 1, 8, 2), "b": (12, 3, 2, 5), "c": (12, 9, 2, 5),
        "d": (4, 13, 8, 2), "e": (2, 9, 2, 5), "f": (2, 3, 2, 5),
        "g": (4, 7, 8, 2),
    }
    if symbol in segments:
        for name in segments[symbol]:
            rect(data, *positions[name], 15)
    elif symbol == "+":
        rect(data, 7, 3, 2, 10, 15); rect(data, 3, 7, 10, 2, 15)
    elif symbol == "-":
        rect(data, 3, 7, 10, 2, 15)
    else:
        rect(data, 7, 12, 3, 3, 15)
    return bytes(pixel for row in data for pixel in row)


def utility_tile(index: int) -> bytes:
    image = canvas(16)
    if index == 0:  # thermometer
        rect(image, 7, 2, 2, 9, 15); circle(image, 8, 12, 3, 12)
    elif index == 1:  # droplet
        circle(image, 8, 10, 4, 9); rect(image, 7, 3, 2, 6, 9)
    elif index == 2:  # wind
        rect(image, 2, 5, 11, 1, 11); rect(image, 4, 9, 10, 1, 11); rect(image, 2, 13, 8, 1, 11)
    else:  # precipitation
        rect(image, 3, 4, 10, 5, 20); rect(image, 5, 10, 2, 4, 22); rect(image, 10, 10, 2, 4, 22)
    return bytes(pixel for row in image for pixel in row)


def utility_image(index: int) -> list[list[int]]:
    data = utility_tile(index)
    return [list(data[row * 16:(row + 1) * 16]) for row in range(16)]


def halve(image: list[list[int]]) -> list[list[int]]:
    """64x64 -> 32x32.  Nearest-neighbour on purpose: these are index-mapped
    palette entries, so averaging them would invent colours that are not in the
    palette and would blend the #FF transparency key into solid pixels."""
    size = len(image) // 2
    return [[image[y * 2][x * 2] for x in range(size)] for y in range(size)]


def tiles(image: list[list[int]]) -> list[bytes]:
    size = len(image)
    result: list[bytes] = []
    for y in range(0, size, TILE):
        for x in range(0, size, TILE):
            result.append(bytes(image[yy][xx] for yy in range(y, y + TILE) for xx in range(x, x + TILE)))
    return result


def ref(slot: int) -> int:
    return ((slot // 64) << 8) | (slot % 64)


def emit_inc(large: list[list[int]], small: list[list[int]], digits: list[int], utilities: list[int]) -> str:
    lines = [
        "; generated by tools/build_assets.py", "GRAPHICS_ASSET_PAGES EQU 5",
        "GRAPHICS_PALETTE_PAGE EQU 4", "GRAPHICS_PALETTE_OFFSET EQU #3D00",
        "GRAPHICS_ICON_COUNT EQU 15", "",
        "GRAPHICS_ICON_LARGE_REFS:",
    ]
    for refs in large:
        lines.append("        DW      " + ", ".join(f"#{value:04X}" for value in refs))
    lines += ["GRAPHICS_ICON_SMALL_REFS:"]
    for refs in small:
        lines.append("        DW      " + ", ".join(f"#{value:04X}" for value in refs))
    lines += ["GRAPHICS_DIGIT_REFS:", "        DW      " + ", ".join(f"#{value:04X}" for value in digits), "GRAPHICS_UTILITY_REFS:", "        DW      " + ", ".join(f"#{value:04X}" for value in utilities)]
    return "\n".join(lines) + "\n"


def export_defaults(force: bool) -> None:
    colours = palette()
    destinations: list[tuple[Path, list[list[int]]]] = []
    for kind, name in enumerate(WEATHER_ICONS):
        large = weather_icon(kind, 64)
        destinations.append((SOURCE / "weather" / "64" / f"{name}.png", large))
        destinations.append((SOURCE / "weather" / "32" / f"{name}.png", halve(large)))
    for index, name in enumerate(UTILITY_ICONS):
        destinations.append((SOURCE / "ui" / f"{name}.png", utility_image(index)))
    existing = [path for path, _ in destinations if path.exists()]
    if existing and not force:
        names = ", ".join(str(path.relative_to(ROOT)) for path in existing[:3])
        raise SystemExit(
            f"refusing to overwrite editable PNG assets ({names}); use --force only "
            "when intentionally restoring generated defaults"
        )
    for path, image in destinations:
        write_indexed_png(path, image, colours, TRANSPARENT)


def load_sources() -> tuple[
    list[list[list[int]]],
    list[list[list[int]]],
    list[list[list[int]]],
]:
    colours = palette()
    try:
        large = [
            read_sprinter_png(SOURCE / "weather" / "64" / f"{name}.png", 64, colours)
            for name in WEATHER_ICONS
        ]
        small = [
            read_sprinter_png(SOURCE / "weather" / "32" / f"{name}.png", 32, colours)
            for name in WEATHER_ICONS
        ]
        utilities = [
            read_sprinter_png(SOURCE / "ui" / f"{name}.png", 16, colours)
            for name in UTILITY_ICONS
        ]
    except (OSError, ValueError) as exc:
        raise SystemExit(f"invalid graphics source: {exc}") from exc
    return large, small, utilities


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--export-defaults",
        action="store_true",
        help="create the initial editable PNG set and exit",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="allow --export-defaults to overwrite edited PNG files",
    )
    args = parser.parse_args()
    if args.force and not args.export_defaults:
        parser.error("--force is only valid with --export-defaults")
    if args.export_defaults:
        export_defaults(args.force)
        return 0

    large_images, small_images, utility_images = load_sources()
    OUT.mkdir(parents=True, exist_ok=True)
    slots: list[bytes] = []
    large: list[list[int]] = []
    for image in large_images:
        refs = [ref(len(slots) + offset) for offset in range(16)]
        large.append(refs)
        slots.extend(tiles(image))
    digits: list[int] = []
    for char in "0123456789+-.":
        digits.append(ref(len(slots)))
        slots.append(digit_tile(char))
    utilities: list[int] = []
    for image in utility_images[:3]:
        utilities.append(ref(len(slots)))
        slots.extend(tiles(image))
    small: list[list[int]] = []
    for image in small_images:
        refs = [ref(len(slots) + offset) for offset in range(4)]
        small.append(refs)
        slots.extend(tiles(image))
    utilities.append(ref(len(slots)))
    slots.extend(tiles(utility_images[3]))
    if len(slots) != 317:
        raise SystemExit(f"internal tile layout error: {len(slots)} slots before palette")
    slots.extend([bytes([TRANSPARENT]) * 256] * 3)
    pages = [bytearray().join(slots[index:index + 64]) for index in range(0, len(slots), 64)]
    if len(pages) != PAGE_COUNT or any(len(page) != PAGE for page in pages):
        raise SystemExit("tile pages must occupy exactly five 16 KiB pages")
    pages[PALETTE_PAGE][PALETTE_OFFSET:PALETTE_OFFSET + 768] = palette()
    for index, page in enumerate(pages):
        (OUT / f"page{index:02d}.bin").write_bytes(page)
    # Stored sizes, one per page.  Resources ship uncompressed for now, so each
    # entry is a full page; the field exists so reintroducing compression only
    # changes what writes this file, not how the client reads the manifest.
    (OUT / "page_sizes.inc").write_text(
        "; generated by tools/build_assets.py\nGRAPHICS_PAGE_SIZES:\n        DW      "
        + ", ".join(str(len(page)) for page in pages)
        + "\n",
        encoding="ascii",
    )
    (OUT / "graphics_assets.inc").write_text(emit_inc(large, small, digits, utilities), encoding="ascii")
    (OUT / "manifest.json").write_text(json.dumps({"format": "weather-gfx-v1", "page_count": PAGE_COUNT, "page_size": PAGE, "palette_page": PALETTE_PAGE, "palette_offset": PALETTE_OFFSET}, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
