#!/usr/bin/env python3
"""Host-side artifact and source contract checks."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import struct
import zipfile


ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"

EXPECTED_DLLS = {
    "UNETESP.DLL": "f03352df4f4af42683d1fde4a8260d0bd3a55f51b1366f10b5467b38566e9abc",
    "UNETRTL.DLL": "051e53b1a4c10f3a41ddad8ad3f26dd974786ebd821c17f8202fb2d91b702fb1",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"Error: {message}")


def check_runtime_files() -> None:
    require((BUILD / "WEATHER.EXE").is_file(), "WEATHER.EXE is missing")
    require((BUILD / "WEATHERC.EXE").is_file(), "WEATHERC.EXE is missing")
    for name, expected_hash in EXPECTED_DLLS.items():
        data = (BUILD / name).read_bytes()
        require(hashlib.sha256(data).hexdigest() == expected_hash, f"{name} changed while staging")


def check_messages() -> None:
    catalogue = json.loads((ROOT / "resources/messages.json").read_text(encoding="utf-8"))
    generated = (BUILD / "generated/messages.inc").read_text(encoding="ascii")
    for label, value in catalogue.items():
        require(f"{label}:" in generated, f"generated message {label} is missing")
        value.encode("cp866")


def check_graphics_sources() -> None:
    large = sorted((ROOT / "resources/gfx/weather/64").glob("*.png"))
    small = sorted((ROOT / "resources/gfx/weather/32").glob("*.png"))
    utility = sorted((ROOT / "resources/gfx/ui").glob("*.png"))
    require(len(large) == 15, f"expected 15 editable 64x64 icons, got {len(large)}")
    require(len(small) == 15, f"expected 15 editable 32x32 icons, got {len(small)}")
    require(len(utility) == 4, f"expected 4 editable UI icons, got {len(utility)}")
    require(
        [path.name for path in large] == [path.name for path in small],
        "64x64 and 32x32 weather icon names differ",
    )
    for path in large + small + utility:
        require(
            path.read_bytes().startswith(b"\x89PNG\r\n\x1a\n"),
            f"editable graphics source is not PNG: {path}",
        )


def check_source_contract() -> None:
    weather_source = (ROOT / "src" / "weatherc.asm").read_text(encoding="utf-8")
    graphics_ui_source = (ROOT / "src" / "graphics_ui.asm").read_text(encoding="utf-8")
    console_source = "\n".join(
        (ROOT / "src" / name).read_text(encoding="utf-8")
        for name in ("weatherc.asm", "config.asm", "wx1.asm", "text_ui.asm", "transport.asm")
    )
    graphics_source = "\n".join(
        (ROOT / "src" / name).read_text(encoding="utf-8")
        for name in ("weather.asm", "graphics_ui.asm")
    )
    source = console_source + "\n" + graphics_source
    for token in (
        'INCLUDE "libman.asm"',
        "UNET_FN_GETCAPS",
        "UNET_FN_STATUS",
        "UNET_FN_NETINIT",
        "UNET_FN_NETDONE",
        "UNET_FN_CONNECT",
        "UNET_FN_SEND",
        "UNET_FN_RECV",
        "UNET_FN_CLOSE",
        "UNET_FN_LASTERR",
        "LIBMAN.l_load",
        "LIBMAN_DIAGNOSTICS",
        "LIBMAN.l_load_stage",
        "LIBMAN.l_init_status",
        "LIBMAN.l_info",
        "LIBMAN.l_call",
        "LIBMAN.l_free",
    ):
        require(token in source, f"runtime contract token is missing: {token}")
    require((ROOT / "src" / "config.asm").is_file(), "configuration module is missing")
    require((ROOT / "src" / "transport.asm").is_file(), "Gopher transport module is missing")
    require((ROOT / "src" / "wx1.asm").is_file(), "WX1 parser module is missing")
    require((ROOT / "src" / "text_ui.asm").is_file(), "text UI module is missing")
    for token in (
        "WX1_FEED",
        "WX1_EOL_CRLF",
        "WX1_EOL_CR",
        "WX1_EOL_LF",
        "TEXT_RENDER_FORECAST",
        "ATTEMPT_START",
        "DSS_WAITKEY",
    ):
        require(token in source, f"text MVP contract token is missing: {token}")
    require("RESPONSE_BUFFER" not in source, "text MVP must not retain the full raw response")
    require("AFNT320.DLL" in graphics_source, "graphics target must load AFNT320")
    require("GFX320.DLL" in graphics_source, "graphics target must load GFX320")
    asset_builder = (ROOT / "tools/build_assets.py").read_text(encoding="utf-8")
    require(
        "read_sprinter_png" in asset_builder and 'SOURCE = ROOT / "resources" / "gfx"' in asset_builder,
        "graphics build must consume the editable PNG sources",
    )
    require(
        "HRUST_DEPACK" in graphics_ui_source
        and "GRAPHICS_PACKED_TOTAL" in graphics_ui_source,
        "graphics client must unpack the one-page Hrust resource tail",
    )
    require(
        'INCLUDE "hrust_depack.asm"' in weather_source,
        "WEATHER.EXE must assemble the Hrust depacker",
    )
    require(
        (ROOT / "src" / "hrust_depack.asm").is_file()
        and (ROOT / "tests" / "z80" / "t_hrust.asm").is_file(),
        "the runtime depacker and its Z80 harness are required",
    )
    require(
        weather_source.index("CALL    GRAPHICS_STAGE_ASSETS")
        < weather_source.index("ATTEMPT_START:"),
        "PRELOAD resources must be staged before the first network attempt",
    )
    require(
        graphics_ui_source.index("CALL    GRAPHICS_CLOSE_PRIMARY")
        < graphics_ui_source.index("GRAPHICS_BOOT:"),
        "the PRELOAD EXE must be closed before deferred decompression/network use",
    )
    close_primary = graphics_ui_source[
        graphics_ui_source.index("GRAPHICS_CLOSE_PRIMARY:"):
        graphics_ui_source.index("GRAPHICS_BOOT_ERROR:")
    ]
    require(
        "CP      0FFh" in close_primary and "DSS_CLOSE_FILE" in close_primary,
        "DSS file handle 0 is valid; PRELOAD close must use 0xff as its sentinel",
    )
    # A truncated read shows up neither in carry nor in the status byte: DSS
    # compares position+size against the file size with SBC and treats "equal"
    # as an overrun, so a read ending exactly at EOF reports #FF with every
    # byte delivered - which the last resource page always does (Estex-DSS
    # API/Read.asm, .TEST_SIZE).  The returned byte count in DE is the only
    # sound check.
    staging = graphics_ui_source[
        graphics_ui_source.index("GRAPHICS_STAGE_ASSETS:"):
        graphics_ui_source.index("GRAPHICS_BOOT:")
    ]
    reads = staging.split("LD      C, DSS_READ_FILE\n        RST     DSS\n")
    require(len(reads) == 3, "staging is expected to issue exactly two file reads")
    for epilogue in reads[1:]:
        code = [
            line.strip() for line in epilogue.splitlines()
            if line.strip() and not line.strip().startswith(";")
        ]
        window = code[:5]           # carry test, count, OR A, SBC, its branch
        require(
            any(line.startswith(("JR      C,", "JP      C,")) for line in window)
            and any(line.startswith("SBC     HL, DE") for line in window),
            "every DSS_READ_FILE in staging must compare the byte count DSS "
            "returns in DE; carry and the status byte both miss a short read",
        )
        require(
            not any(line.startswith("OR      A") and window[window.index(line) + 1:]
                    and not window[window.index(line) + 1].startswith("SBC     HL, DE")
                    for line in window),
            "the status byte is #FF for a legitimate exactly-at-EOF read and "
            "must not be branched on",
        )
    require(
        "LD      H, 0\n" not in graphics_ui_source,
        "generic DSS SETWIN treats H=0 as an error and substitutes WIN1, "
        "which pages the running program out; select a window explicitly",
    )
    require(
        "OUT     (082h), A" in graphics_ui_source
        and "LD      DE, 0" in graphics_ui_source,
        "Hrust output must use WIN0; WIN2 contains WEATHER.EXE and its stack",
    )
    # BIOS EMM_FN5 needs a 256-byte destination, so the physical page list is
    # collected in the borrowed config buffer and consumed by the very next
    # call.  Nothing may run between the producer and the consumer.
    require(
        "ASSET_PHYSICAL_PAGES" not in graphics_source + weather_source,
        "EMM_FN5 must not write into a short dedicated field: it overruns into "
        "GRAPHICS_SAVED_WIN0/WIN2/WIN3 and corrupts the page ports",
    )
    require(
        graphics_ui_source.index("CALL    GRAPHICS_BOOT")
        < graphics_ui_source.index("CALL    GRAPHICS_LOAD_LIBRARIES")
        < graphics_ui_source.index("CALL    GRAPHICS_DRAW\n"),
        "the borrowed page-list buffer is only valid from GRAPHICS_BOOT until "
        "GRAPHICS_LOAD_LIBRARIES consumes it",
    )
    # libman returns a table index in L with H forced to 0, so handle 0 belongs
    # to the first library loaded.  Testing the handle for zero reloads GFX320
    # on every refresh and leaks a table slot plus a two-page block each time.
    for token in ("LD      A, (GFX_HANDLE)", "LD      A, (AFNT_HANDLE)"):
        require(
            token not in graphics_ui_source,
            "libman handle 0 is valid; gate DLL loading on GRAPHICS_LIBS_LOADED "
            f"rather than testing the handle ({token})",
        )
    require(
        "GRAPHICS_LIBS_LOADED" in graphics_ui_source + weather_source,
        "the DLL pair needs a load flag distinct from the handle values",
    )
    for token in ("GRAPHICS_MARK", "GRAPHICS_REPORT_FAIL", "DSS_PUTCHAR"):
        require(
            token not in graphics_ui_source,
            f"graphics frontend must not emit debug console markers ({token})",
        )
    # Nothing of this program may live in WIN1.  DSS's SETVMOD reaches BIOS
    # WIN_COPY, which maps video page #50 over WIN1 for the duration of the
    # text-screen save while keeping the displaced page number on the CALLER's
    # stack (FUNC_LOW_PRINT.ASM:1506-1556).  With the stack in WIN1 that pops
    # back a byte of video memory and pushes it into the WIN1 page port, which
    # resets the machine.
    require(
        "EXE_LOAD_ADDRESS        EQU 08100h" in weather_source
        and "04100h" not in weather_source,
        "both clients must load at #8100; a WIN1-resident program cannot "
        "survive a DSS video mode switch",
    )
    require(
        graphics_ui_source.count("LD      A, 1\n        CALL    LIBMAN.l_load") == 2,
        "GFX320 and AFNT320 must map into WIN1, since WIN2 now holds this "
        "program and its stack",
    )
    # Rendering defects that were each visible on hardware and are easy to
    # reintroduce, since all four look plausible in isolation.
    require(
        "LD      DE, WD_MIN" in graphics_ui_source,
        "the first day row is WD_MIN; reading the record base prints WD_YEAR "
        "as tenths of a degree",
    )
    require(
        "AND     3\n        JR      NZ, .NEXT" not in graphics_ui_source,
        "tile grid width must come from the caller, not a hardcoded 4-wide row",
    )
    require(
        graphics_ui_source.count("CALL    GRAPHICS_DAY_COUNT") == 2,
        "both day loops must honour WM_DAY_COUNT instead of assuming six",
    )
    require(
        "CALL    GRAPHICS_FORMAT_LOCATION" in graphics_ui_source
        and "LD      IX, 190" not in graphics_ui_source,
        "location and country must be composed into one variable-width string",
    )
    require(
        "CALL    GRAPHICS_APPEND_CELSIUS" in graphics_ui_source
        and "LD      IX, 161" not in graphics_ui_source,
        "the Celsius unit must be appended to the formatted temperature",
    )
    require("ANTONFNT" not in source, "runtime must not reference legacy ANTONFNT")
    require(
        "ENV_VALUE_SIZE  EQU 256" in source,
        "ENV_GET buffer must cover DSS's maximum environment value",
    )


def check_graphics_exe() -> None:
    data = (BUILD / "WEATHER.EXE").read_bytes()
    require(data[:3] == b"EXE" and data[3] == 1, "WEATHER.EXE header is invalid")
    loader_size = struct.unpack_from("<H", data, 8)[0]
    require(loader_size > 0, "WEATHER.EXE must be preload-enabled")
    tail = 0x200 + loader_size
    require(data[tail:tail + 4] == b"WFG1", "graphics manifest is missing")
    version, count, size = struct.unpack_from("<BBH", data, tail + 4)
    require((version, count, size) == (1, 5, 0x4000), "graphics manifest has invalid geometry")
    sizes = struct.unpack_from("<5H", data, tail + 12)
    require(all(0 < size <= 0x4000 for size in sizes), "packed graphic page has invalid size")
    require(sum(sizes) <= 0x4000, "packed graphic tail must fit its staging page")
    require(len(data) == tail + 22 + sum(sizes), "manifest does not describe WEATHER.EXE tail")


def check_zip_if_present() -> None:
    archive = ROOT / "distr/weather-forecast.zip"
    if not archive.exists():
        return
    with zipfile.ZipFile(archive) as package:
        names = sorted(package.namelist())
    require(
        names == ["AFNT320.DLL", "GFX320.DLL", "README.TXT", "UNETESP.DLL", "UNETRTL.DLL", "WEATHER.EXE", "WEATHERC.EXE"],
        f"unexpected ZIP contents: {names}",
    )


def main() -> int:
    check_runtime_files()
    check_messages()
    check_graphics_sources()
    check_source_contract()
    check_graphics_exe()
    check_zip_if_present()
    print("Host artifact tests: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
