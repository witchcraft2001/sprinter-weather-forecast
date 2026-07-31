#!/usr/bin/env python3
"""Append the WEATHER.EXE WFG1 resource tail after its resident image."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


HEADER = 0x200
MANIFEST_MAGIC = b"WFG1"
PAGE_COUNT = 5
PAGE_SIZE = 0x4000
PALETTE_PAGE = 4
PALETTE_OFFSET = 0x3D00


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("raw", type=Path)
    parser.add_argument("assets", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    raw = args.raw.read_bytes()
    if len(raw) < HEADER or raw[:3] != b"EXE":
        raise SystemExit("raw input is not a DSS EXE")
    loader_size = struct.unpack_from("<H", raw, 8)[0]
    resident_end = HEADER + loader_size
    if loader_size == 0 or resident_end > len(raw):
        raise SystemExit("invalid WEATHER resident loader size")

    streams = [
        (args.assets / f"page{index:02d}.hst").read_bytes()
        for index in range(PAGE_COUNT)
    ]
    if any(not stream or len(stream) > PAGE_SIZE for stream in streams):
        raise SystemExit("each packed graphic stream must fit one DSS page")
    if sum(map(len, streams)) > PAGE_SIZE:
        raise SystemExit("packed graphic streams must fit the one-page staging buffer")
    manifest = struct.pack(
        "<4sBBHBBH5H",
        MANIFEST_MAGIC, 1, PAGE_COUNT, PAGE_SIZE, PALETTE_PAGE, 0,
        PALETTE_OFFSET, *(len(stream) for stream in streams),
    )
    assert len(manifest) == 22
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(raw[:resident_end] + manifest + b"".join(streams))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
