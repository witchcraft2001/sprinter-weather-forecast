#!/usr/bin/env python3
"""Run the actual graphical runtime with deterministic DSS/DLL boundaries."""
import os
from pathlib import Path
import subprocess

from check_exe import symbol_value

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
TESTS = BUILD / "tests"
TESTS.mkdir(exist_ok=True)
symbols = (BUILD / "WEATHER.runtime.sym").read_text()
loader_symbols = (BUILD / "WEATHER.loader.sym").read_text()
names = {
    "ATTEMPT_START": "MAIN.ATTEMPT_START",
    "INTERVAL": "MAIN.GRAPHICS_INTERVAL",
    "ATTEMPT_FINISH": "MAIN.ATTEMPT_FINISH",
    "MODE_ACTIVE": "MAIN.GRAPHICS_MODE_ACTIVE",
    "LIBCALL": "LIBMAN.l_call",
}
(TESTS / "runtime_symbols.inc").write_text("\n".join(
    f"R_{key} EQU {symbol_value(symbols, value)}"
    for key, value in names.items()
) + f"\nL_ARG_OK EQU {symbol_value(loader_symbols, 'LOADER_START.ARG_OK')}\n")
(TESTS / "runtime_test.bin").write_bytes((BUILD / "WEATHER.RUNTIME").read_bytes())
(TESTS / "loader_test.bin").write_bytes((BUILD / "WEATHER.LOADER.EXE").read_bytes()[512:])
binary = TESTS / "t_graphics_runtime.bin"
dump = TESTS / "t_graphics_runtime.out"
ticks = os.environ.get("TICKS", "/Users/dmitry/dev/zx/sprinter/z88dk/bin/z88dk-ticks")
for psp in (0x8003, 0x8080):
    for interval in (1, 5):
        subprocess.run(["sjasmplus", "--nologo", "-I", str(TESTS), "-I",
                        str(ROOT / "tests/z80"), f"-DPSP_ADDRESS={psp}",
                        f"-DINTERVAL={interval}", f"--raw={binary}",
                        str(ROOT / "tests/z80/t_graphics_runtime.asm")], check=True)
        dump.unlink(missing_ok=True)
        subprocess.run([ticks, "-pc", "0", "-int", "2000", "-counter",
                        str((interval * 120 + 5) * 50 * 2000), "-output",
                        str(dump), str(binary)], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
        data = dump.read_bytes()
        case = f"PSP={psp:#06x}, interval={interval}"
        assert data[0xE001] == 0xA5, f"runtime test did not finish ({case})"
        assert data[0xE000] == 0, f"runtime assertion {data[0xE002]} failed ({case})"
print("Z80 runtime integration: OK (both DSS PSP layouts, EI/HALT/RTC, two refreshes at 1/5 minutes)")
