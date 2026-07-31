#!/usr/bin/env python3
"""Append the WFG2 runtime and Hrust streams after the primary loader."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


HEADER = 0x200
MANIFEST_MAGIC = b"WFG2"
PAGE_COUNT = 5
PAGE_SIZE = 0x4000
RUNTIME_OFFSET = 0x0100
PALETTE_PAGE = 4
PALETTE_OFFSET = 0x3D00


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("loader", type=Path)
    parser.add_argument("runtime", type=Path)
    parser.add_argument("assets", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    loader = args.loader.read_bytes()
    if len(loader) < HEADER or loader[:3] != b"EXE":
        raise SystemExit("loader input is not a DSS EXE")
    loader_size = struct.unpack_from("<H", loader, 8)[0]
    loader_end = HEADER + loader_size
    if loader_size == 0 or loader_end != len(loader):
        raise SystemExit("primary loader length does not match its EXE header")
    runtime = args.runtime.read_bytes()
    if not runtime or len(runtime) > PAGE_SIZE - RUNTIME_OFFSET:
        raise SystemExit("resident runtime must fit one DSS page at offset 0x100")

    streams = [
        (args.assets / f"page{index:02d}.hst").read_bytes()
        for index in range(PAGE_COUNT)
    ]
    if any(not stream or len(stream) > PAGE_SIZE for stream in streams):
        raise SystemExit("each packed graphic stream must fit one DSS page")
    # The loader reuses one scratch page per stream, so the total tail has no
    # one-page limit; only an individual Hrust stream does.
    manifest = struct.pack(
        "<4sBBHBBHH5H",
        MANIFEST_MAGIC, 2, PAGE_COUNT, PAGE_SIZE, PALETTE_PAGE, 0,
        len(runtime), PALETTE_OFFSET, *(len(stream) for stream in streams),
    )
    assert len(manifest) == 24
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(loader + manifest + runtime + b"".join(streams))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
