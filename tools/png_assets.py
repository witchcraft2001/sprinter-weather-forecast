#!/usr/bin/env python3
"""Minimal editor-friendly PNG reader/writer for indexed Sprinter assets.

The reader accepts non-interlaced 8-bit indexed, RGB and RGBA PNG files and
implements all five PNG row filters.  The writer emits an indexed PNG with the
project palette and transparency at index 0xff.  No third-party Python module
is required.
"""

from __future__ import annotations

import binascii
from pathlib import Path
import struct
import zlib


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def _chunk(kind: bytes, payload: bytes) -> bytes:
    body = kind + payload
    return struct.pack(">I", len(payload)) + body + struct.pack(
        ">I", binascii.crc32(body) & 0xFFFFFFFF
    )


def write_indexed_png(
    path: Path,
    image: list[list[int]],
    palette: bytes,
    transparent: int = 0xFF,
) -> None:
    """Write an 8-bit indexed PNG, preserving Sprinter palette indices."""
    if not image or not image[0]:
        raise ValueError("PNG image is empty")
    width = len(image[0])
    height = len(image)
    if any(len(row) != width for row in image):
        raise ValueError("PNG rows have different widths")
    if len(palette) != 256 * 3:
        raise ValueError("PNG palette must contain exactly 256 RGB colours")
    pixels = bytearray()
    for row in image:
        if any(not 0 <= pixel <= 0xFF for pixel in row):
            raise ValueError("PNG palette index is outside 0..255")
        pixels.append(0)  # filter type: None
        pixels.extend(row)
    alpha = bytearray([0xFF] * 256)
    alpha[transparent] = 0
    payload = (
        PNG_SIGNATURE
        + _chunk("IHDR".encode(), struct.pack(">IIBBBBB", width, height, 8, 3, 0, 0, 0))
        + _chunk(b"PLTE", palette)
        + _chunk(b"tRNS", bytes(alpha))
        + _chunk(b"IDAT", zlib.compress(bytes(pixels), level=9))
        + _chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


def _paeth(left: int, above: int, upper_left: int) -> int:
    estimate = left + above - upper_left
    left_distance = abs(estimate - left)
    above_distance = abs(estimate - above)
    upper_left_distance = abs(estimate - upper_left)
    if left_distance <= above_distance and left_distance <= upper_left_distance:
        return left
    if above_distance <= upper_left_distance:
        return above
    return upper_left


def _unfilter(raw: bytes, width: int, height: int, bpp: int) -> list[bytes]:
    stride = width * bpp
    expected = height * (stride + 1)
    if len(raw) != expected:
        raise ValueError(f"decoded PNG has {len(raw)} bytes, expected {expected}")
    rows: list[bytes] = []
    offset = 0
    previous = bytes(stride)
    for _ in range(height):
        filter_type = raw[offset]
        encoded = raw[offset + 1:offset + 1 + stride]
        offset += stride + 1
        row = bytearray(stride)
        for index, value in enumerate(encoded):
            left = row[index - bpp] if index >= bpp else 0
            above = previous[index]
            upper_left = previous[index - bpp] if index >= bpp else 0
            if filter_type == 0:
                predictor = 0
            elif filter_type == 1:
                predictor = left
            elif filter_type == 2:
                predictor = above
            elif filter_type == 3:
                predictor = (left + above) // 2
            elif filter_type == 4:
                predictor = _paeth(left, above, upper_left)
            else:
                raise ValueError(f"unsupported PNG filter {filter_type}")
            row[index] = (value + predictor) & 0xFF
        previous = bytes(row)
        rows.append(previous)
    return rows


def read_rgba_png(path: Path) -> tuple[int, int, list[list[tuple[int, int, int, int]]]]:
    """Decode a non-interlaced 8-bit indexed/RGB/RGBA PNG to RGBA pixels."""
    data = path.read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError(f"{path}: not a PNG file")
    offset = len(PNG_SIGNATURE)
    width = height = bit_depth = colour_type = interlace = None
    palette: list[tuple[int, int, int]] | None = None
    transparency = b""
    compressed = bytearray()
    saw_end = False
    while offset + 12 <= len(data):
        length = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset + 4:offset + 8]
        payload_start = offset + 8
        payload_end = payload_start + length
        crc_end = payload_end + 4
        if crc_end > len(data):
            raise ValueError(f"{path}: truncated PNG chunk")
        payload = data[payload_start:payload_end]
        expected_crc = struct.unpack_from(">I", data, payload_end)[0]
        actual_crc = binascii.crc32(kind + payload) & 0xFFFFFFFF
        if actual_crc != expected_crc:
            raise ValueError(f"{path}: bad {kind.decode('ascii', 'replace')} CRC")
        if kind == b"IHDR":
            if length != 13:
                raise ValueError(f"{path}: invalid IHDR")
            width, height, bit_depth, colour_type, compression, filtering, interlace = (
                struct.unpack(">IIBBBBB", payload)
            )
            if compression != 0 or filtering != 0:
                raise ValueError(f"{path}: unsupported PNG compression/filter method")
        elif kind == b"PLTE":
            if length % 3:
                raise ValueError(f"{path}: invalid PLTE")
            palette = [
                tuple(payload[index:index + 3])  # type: ignore[arg-type]
                for index in range(0, length, 3)
            ]
        elif kind == b"tRNS":
            transparency = payload
        elif kind == b"IDAT":
            compressed.extend(payload)
        elif kind == b"IEND":
            saw_end = True
            break
        offset = crc_end
    if not saw_end or None in (width, height, bit_depth, colour_type, interlace):
        raise ValueError(f"{path}: incomplete PNG")
    assert width is not None and height is not None
    assert bit_depth is not None and colour_type is not None and interlace is not None
    if bit_depth != 8:
        raise ValueError(f"{path}: only 8-bit PNG assets are supported")
    if interlace != 0:
        raise ValueError(f"{path}: interlaced PNG assets are not supported")
    channels = {2: 3, 3: 1, 6: 4}.get(colour_type)
    if channels is None:
        raise ValueError(f"{path}: use indexed, RGB or RGBA PNG")
    rows = _unfilter(zlib.decompress(bytes(compressed)), width, height, channels)
    result: list[list[tuple[int, int, int, int]]] = []
    for row in rows:
        pixels: list[tuple[int, int, int, int]] = []
        for x in range(width):
            start = x * channels
            if colour_type == 6:
                red, green, blue, alpha = row[start:start + 4]
            elif colour_type == 2:
                red, green, blue = row[start:start + 3]
                alpha = 0xFF
            else:
                index = row[start]
                if palette is None or index >= len(palette):
                    raise ValueError(f"{path}: palette index {index} is undefined")
                red, green, blue = palette[index]
                alpha = transparency[index] if index < len(transparency) else 0xFF
            pixels.append((red, green, blue, alpha))
        result.append(pixels)
    return width, height, result


def read_sprinter_png(
    path: Path,
    size: int,
    palette: bytes,
    transparent: int = 0xFF,
) -> list[list[int]]:
    """Load a PNG and map exact opaque RGB colours to Sprinter indices."""
    width, height, rgba = read_rgba_png(path)
    if (width, height) != (size, size):
        raise ValueError(f"{path}: expected {size}x{size}, got {width}x{height}")
    colour_to_index: dict[tuple[int, int, int], int] = {}
    for index in range(256):
        colour = tuple(palette[index * 3:index * 3 + 3])
        colour_to_index.setdefault(colour, index)  # prefer standard low indices
    image: list[list[int]] = []
    for y, row in enumerate(rgba):
        target_row: list[int] = []
        for x, (red, green, blue, alpha) in enumerate(row):
            if alpha == 0:
                target_row.append(transparent)
                continue
            if alpha != 0xFF:
                raise ValueError(f"{path}:{x},{y}: alpha must be 0 or 255")
            colour = (red, green, blue)
            if colour not in colour_to_index:
                raise ValueError(
                    f"{path}:{x},{y}: RGB {colour} is outside the project palette"
                )
            target_row.append(colour_to_index[colour])
        image.append(target_row)
    return image
