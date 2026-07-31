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
    parser.add_argument("runtime_symbols", type=Path, nargs="?")
    args = parser.parse_args()

    raw = args.exe.read_bytes()
    if len(raw) <= 512:
        fail(f"{args.exe.name} contains no body after its 512-byte header")
    if raw[:3] != b"EXE" or raw[3] != 1:
        fail("invalid DSS EXE v1 signature")

    code_offset = struct.unpack_from("<I", raw, 4)[0]
    loader_size = struct.unpack_from("<H", raw, 8)[0]
    load_address, entry, stack = struct.unpack_from("<HHH", raw, 16)
    if code_offset != 0x200:
        fail(f"code offset is 0x{code_offset:08x}, expected 0x00000200")
    # Both clients load at the stock #8100.  WIN1 is not a viable home for a
    # resident program: DSS's SETVMOD maps video page #50 over WIN1 through
    # BIOS WIN_COPY while keeping the displaced page number on the caller's
    # stack, which resets the machine if that stack is in WIN1 too.
    graphics = loader_size != 0
    if load_address != 0x8100 or entry != 0x8100:
        fail(f"load/entry is {load_address:04x}/{entry:04x}, expected 8100/8100")
    if not 0x8100 < stack <= 0xC000:
        fail(f"stack 0x{stack:04x} lies outside WIN2")

    symbols = (args.runtime_symbols or args.symbols).read_text(
        encoding="utf-8", errors="replace"
    )
    image_end = symbol_value(symbols, "MAIN.IMAGE_END")
    bss_base = symbol_value(symbols, "MAIN.BSS_BASE")
    bss_end = symbol_value(symbols, "MAIN.BSS_END")
    stack_top = symbol_value(symbols, "MAIN.STACK_TOP")
    image_base = 0x8100
    image_limit = 0xC000
    if not (image_base < bss_base <= bss_end < stack_top == image_end):
        fail("invalid image/BSS/stack ordering")
    if args.runtime_symbols is None and stack != stack_top:
        fail("header stack does not match MAIN.STACK_TOP")
    headroom = image_limit - stack_top
    # Bytes above STACK_TOP are neither stack nor image - the stack grows down.
    # This is only a guard against sitting flush against the window edge; the
    # load-bearing check is IMAGE_END < image_limit above.  The console client
    # happens to have far more slack, which is not a requirement.
    minimum_headroom = 0x80
    if headroom < minimum_headroom:
        fail(
            f"WIN2 headroom is only "
            f"{headroom} bytes, need at least {minimum_headroom}"
        )
    if graphics:
        expected_min = 512 + loader_size
        if len(raw) < expected_min:
            fail("graphics EXE is shorter than its primary loader")
        if args.runtime_symbols is not None:
            loader_symbols = args.symbols.read_text(encoding="utf-8", errors="replace")
            if symbol_value(loader_symbols, "WEATHER_LOADER_SIZE") != loader_size:
                fail("header loader size does not match the primary loader")
            tail = expected_min
            if raw[tail:tail + 4] != b"WFG2":
                fail("graphics EXE has no WFG2 loader manifest")
            runtime_size = struct.unpack_from("<H", raw, tail + 10)[0]
            stream_sizes = struct.unpack_from("<5H", raw, tail + 14)
            if runtime_size != image_end - image_base:
                fail("WFG2 runtime size does not match the runtime image")
            if len(raw) != tail + 24 + runtime_size + sum(stream_sizes):
                fail("WFG2 manifest does not describe the graphics EXE tail")
    elif 512 + (image_end - image_base) != len(raw):
        fail("EXE file size does not match assembled image end")

    print(
        f"{args.exe.name}: OK "
        f"(file={len(raw)} bytes, image={image_end - image_base} bytes, "
        f"BSS={bss_end - bss_base} bytes, stack={stack_top - bss_end} bytes, "
        f"headroom={headroom} bytes)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
