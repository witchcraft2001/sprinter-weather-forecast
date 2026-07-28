#!/usr/bin/env python3
"""Validate the DSS EXE header and the assembled WIN2 memory map."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import struct


def fail(message: str) -> None:
    raise SystemExit(f"Error: {message}")


def symbol_value(symbols: str, name: str) -> int:
    patterns = (
        rf"^{re.escape(name)}:\s+EQU\s+0x([0-9A-Fa-f]+)",
        rf"^{re.escape(name)}:\s+EQU\s+([0-9A-Fa-f]+)h",
        rf"^{re.escape(name)}:\s+EQU\s+([0-9]+)",
    )
    for pattern in patterns:
        match = re.search(pattern, symbols, re.MULTILINE)
        if match:
            base = 10 if pattern.endswith(r"([0-9]+)") else 16
            return int(match.group(1), base)
    fail(f"symbol {name} was not found")
    raise AssertionError


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("exe", type=Path)
    parser.add_argument("symbols", type=Path)
    args = parser.parse_args()

    raw = args.exe.read_bytes()
    if len(raw) <= 512:
        fail("WEATHER.EXE contains no body after its 512-byte header")
    if raw[:3] != b"EXE" or raw[3] != 1:
        fail("invalid DSS EXE v1 signature")

    code_offset = struct.unpack_from("<I", raw, 4)[0]
    loader_size = struct.unpack_from("<H", raw, 8)[0]
    load_address, entry, stack = struct.unpack_from("<HHH", raw, 16)
    if code_offset != 0x200:
        fail(f"code offset is 0x{code_offset:08x}, expected 0x00000200")
    if loader_size != 0:
        fail(f"unexpected primary loader size: {loader_size}")
    if load_address != 0x8100 or entry != 0x8100:
        fail(f"load/entry is {load_address:04x}/{entry:04x}, expected 8100/8100")
    if not 0x8100 < stack <= 0xC000:
        fail(f"stack 0x{stack:04x} lies outside WIN2")

    symbols = args.symbols.read_text(encoding="utf-8", errors="replace")
    image_end = symbol_value(symbols, "MAIN.IMAGE_END")
    bss_base = symbol_value(symbols, "MAIN.BSS_BASE")
    bss_end = symbol_value(symbols, "MAIN.BSS_END")
    stack_top = symbol_value(symbols, "MAIN.STACK_TOP")
    if not (0x8100 < bss_base <= bss_end < stack_top == image_end):
        fail("invalid image/BSS/stack ordering")
    if stack != stack_top:
        fail("header stack does not match MAIN.STACK_TOP")
    if 512 + (image_end - 0x8100) != len(raw):
        fail("EXE file size does not match assembled image end")

    print(
        "WEATHER.EXE: OK "
        f"(file={len(raw)} bytes, image={image_end - 0x8100} bytes, "
        f"BSS={bss_end - bss_base} bytes, stack={stack_top - bss_end} bytes)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
