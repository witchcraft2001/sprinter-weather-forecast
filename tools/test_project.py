#!/usr/bin/env python3
"""Host-side artifact and source contract checks."""

from __future__ import annotations

import hashlib
import json
import re
import struct
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"

UNET_MANIFEST = json.loads(
    (ROOT / "extern/unet_libs_asm/extern/core/dll/manifest.json").read_text(
        encoding="utf-8"
    )
)
EXPECTED_DLLS = {name: entry["sha256"] for name, entry in UNET_MANIFEST.items()}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"Error: {message}")


def check_runtime_files() -> None:
    require((BUILD / "WEATHER.EXE").is_file(), "WEATHER.EXE is missing")
    require((BUILD / "WEATHERC.EXE").is_file(), "WEATHERC.EXE is missing")
    for name, expected_hash in EXPECTED_DLLS.items():
        data = (BUILD / name).read_bytes()
        require(hashlib.sha256(data).hexdigest() == expected_hash, f"{name} changed while staging")
    require(
        {path.name for path in BUILD.glob("UNET*.DLL")} == set(EXPECTED_DLLS),
        "build UNET DLL set differs from the core manifest",
    )


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
    graphics_clock_source = (ROOT / "src" / "graphics_clock.asm").read_text(encoding="utf-8")
    graphics_frame_source = (ROOT / "src" / "graphics_frame.asm").read_text(encoding="utf-8")
    graphics_timer_source = (ROOT / "src" / "graphics_timer.asm").read_text(encoding="utf-8")
    loader_source = (ROOT / "src" / "weather_loader.asm").read_text(encoding="utf-8")
    message_catalogue = json.loads(
        (ROOT / "resources/messages.json").read_text(encoding="utf-8")
    )
    loader_page_loop = loader_source[
        loader_source.index(".PAGE:") : loader_source.index(
            "LD      A, (L_FILE_HANDLE)", loader_source.index(".PAGE:")
        )
    ]
    console_source = "\n".join(
        (ROOT / "src" / name).read_text(encoding="utf-8")
        for name in ("weatherc.asm", "config.asm", "wx1.asm", "text_ui.asm", "transport.asm")
    )
    graphics_source = "\n".join(
        (ROOT / "src" / name).read_text(encoding="utf-8")
        for name in (
            "weather.asm",
            "graphics_ui.asm",
            "graphics_frame.asm",
            "graphics_timer.asm",
            "graphics_clock.asm",
        )
    )
    source = console_source + "\n" + graphics_source
    setup_start = weather_source.index("        CALL    UNETLD.SELECT")
    setup_end = weather_source.index("        CALL    GOPHER_FETCH", setup_start)
    setup_source = weather_source[setup_start:setup_end]
    setup_steps = (
        "CALL    UNETLD.SELECT",
        "CALL    UNETLD.LOAD",
        "CALL    UNETLD.REQUIRE",
        "LD      A, UNET_OPT_CANCELKEYS",
        "CALL    UNETLD.CALL",
        "CALL    UNETLD.NETSTART",
    )
    setup_positions = [setup_source.index(step) for step in setup_steps]
    require(
        setup_positions == sorted(setup_positions),
        "network setup must follow SELECT/LOAD/REQUIRE/SETOPT/NETSTART order",
    )
    for token in (
        'INCLUDE "libman.asm"',
        'INCLUDE "unetld.asm"',
        "UNETLD.RESET",
        "UNETLD.SELECT",
        "UNETLD.LOAD",
        "UNETLD.REQUIRE",
        "UNETLD.NETSTART",
        "UNETLD.CALL",
        "UNETLD.UNLOAD",
        "UNETLD_STATE_BASE",
        "UNET_OPT_CANCELKEYS",
        "NERR_CANCEL",
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
        "LIBMAN.l_call",
        "LIBMAN.l_free",
    ):
        require(token in source, f"runtime contract token is missing: {token}")
    for token in ("SELECT_BACKEND", "CALL_UNET", "BACKEND_WIFI", "BACKEND_RTL", "UNETESP.DLL", "UNETRTL.DLL"):
        require(token not in source, f"runtime must not contain a known-backend list: {token}")
    require((ROOT / "src" / "config.asm").is_file(), "configuration module is missing")
    require((ROOT / "src" / "transport.asm").is_file(), "Gopher transport module is missing")
    dss_path = ROOT / "src" / "dss.inc"
    require(dss_path.is_file(), "local minimal DSS bindings are missing")
    dss_source = dss_path.read_text(encoding="utf-8")
    for name, value in {
        "DSS": "010h",
        "DSS_OPEN_FILE": "011h",
        "DSS_CLOSE_FILE": "012h",
        "DSS_READ_FILE": "013h",
        "DSS_MOVE_FP": "015h",
        "DSS_SYSTIME": "021h",
        "DSS_WAITKEY": "030h",
        "DSS_SCANKEY": "031h",
        "DSS_KCLEAR": "035h",
        "DSS_SETWIN1": "039h",
        "DSS_SETWIN3": "03Bh",
        "DSS_GETMEM": "03Dh",
        "DSS_FREEMEM": "03Eh",
        "DSS_EXIT": "041h",
        "DSS_ENVIRON": "046h",
        "DSS_APPINFO": "047h",
        "DSS_SETVMOD": "050h",
        "DSS_GETVMOD": "051h",
        "DSS_PUTCHAR": "05Bh",
        "DSS_PCHARS": "05Ch",
        "ENV_GET": "001h",
        "APPINFO_EXE_HOMEDIR": "001h",
        "SEEK_END": "2",
        "FM_READ": "1",
        "E_FILE_NOT_FOUND": "3",
        "DSS_VMOD_G320": "081h",
    }.items():
        require(
            re.search(rf"^{name}\s+EQU\s+{value}$", dss_source, re.MULTILINE)
            is not None,
            f"local DSS binding differs from Estex DSS: {name}",
        )
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
        "HRUST_DEPACK" not in graphics_ui_source + weather_source,
        "resident graphics runtime must not retain the Hrust depacker",
    )
    require(
        'INCLUDE "hrust_depack.asm"' in loader_source
        and "WFG2" in loader_source
        and "L_TRAMPOLINE" in loader_source,
        "primary loader must own WFG2, Hrust and the WIN2 handoff",
    )
    banner = 'Weather Forecast v.0.1.2 by Dmitry Mikhalchenkov.'
    require(
        banner in loader_source
        and "LD      HL, L_BANNER\n        LD      C, DSS_PCHARS\n        RST     DSS"
        in loader_source
        and loader_source.index("LD      HL, L_BANNER")
        < loader_source.index("CALL    L_READ_EXACT"),
        "primary loader must print the version/author banner before WFG2 loading",
    )
    distribution_readme = (ROOT / "resources" / "README.ru.txt").read_text(
        encoding="utf-8"
    )
    for identity in ("Dmitry Mikhalchenkov", "2:5030/1997.10"):
        require(
            identity in distribution_readme,
            f"distribution description is missing author identity: {identity}",
        )
    for config_detail in (
        "HOST=go.sprinter.ru",
        "PORT=70",
        "SELECTOR=/weather/zx",
        "LOCATION=Almaty,KZ",
        "NET=WIFI",
        "NET=RTL",
        "NET=509B",
    ):
        require(
            config_detail in distribution_readme,
            f"distribution description is missing WEATHER.CFG detail: {config_detail}",
        )
    require(
        (ROOT / "src" / "hrust_depack.asm").is_file()
        and (ROOT / "tests" / "z80" / "t_hrust.asm").is_file(),
        "the loader depacker and its Z80 harness are required",
    )
    require(
        (ROOT / "tests" / "z80" / "t_config.asm").is_file()
        and "Z80 config harness" in (ROOT / "tools" / "run_z80_tests.sh").read_text(
            encoding="utf-8"
        ),
        "the WEATHER.CFG parser needs its Z80 regression harness",
    )
    require(
        (ROOT / "tests" / "z80" / "t_unetld_select.asm").is_file()
        and "Z80 UNETLD harness" in (ROOT / "tools" / "run_z80_tests.sh").read_text(
            encoding="utf-8"
        ),
        "UNETLD backend selection needs its Z80 regression harness",
    )
    require(
        (ROOT / "tests" / "z80" / "t_interval.asm").is_file()
        and 'INCLUDE "interval.asm"' in loader_source
        and "Z80 interval harness" in (ROOT / "tools" / "run_z80_tests.sh").read_text(
            encoding="utf-8"
        ),
        "WEATHER refresh interval parsing needs its production Z80 harness",
    )
    require(
        (ROOT / "tests" / "z80" / "t_graphics_timer.asm").is_file()
        and "Z80 graphics timer harness" in (ROOT / "tools" / "run_z80_tests.sh").read_text(
            encoding="utf-8"
        ),
        "the graphics refresh countdown needs its Z80 regression harness",
    )
    require(
        (ROOT / "tests" / "z80" / "t_graphics_clock.asm").is_file()
        and "Z80 graphics clock harness" in (ROOT / "tools" / "run_z80_tests.sh").read_text(
            encoding="utf-8"
        ),
        "the HH:MM:SS formatter needs its Z80 regression harness",
    )
    require(
        (ROOT / "tests" / "z80" / "t_graphics_model.asm").is_file()
        and "Z80 graphics model harness" in (ROOT / "tools" / "run_z80_tests.sh").read_text(
            encoding="utf-8"
        ),
        "retry failures need a Z80 regression harness for forecast retention",
    )
    unetld_harness = (ROOT / "tests" / "z80" / "t_unetld_select.asm").read_text(
        encoding="utf-8"
    )
    for scenario in (
        "TEST_WIFI_ALIAS",
        "TEST_DIRECT_TAG",
        "TEST_NO_ENV",
        "TEST_BAD_LENGTHS",
        "TEST_BAD_CHARACTER",
        "TEST_LOAD_MISSING",
        "TEST_WRONG_DLL_NAME",
        "TEST_BAD_ABI",
        "TEST_NO_TCP",
        "TEST_NETSTART_SUCCESS",
        "TEST_NETSTART_STATUS",
        "TEST_UNLOAD_IDEMPOTENT",
    ):
        require(scenario in unetld_harness, f"UNETLD harness scenario is missing: {scenario}")
    require(
        "TEST_TRANSPORT_CANCEL" in (ROOT / "tests" / "z80" / "t_response.asm").read_text(
            encoding="utf-8"
        ),
        "transport harness must exercise UNET cancellation",
    )
    config_source = (ROOT / "src" / "config.asm").read_text(encoding="utf-8")
    require(
        "LD      HL, (CFG_FILE_SIZE)\n        OR      A\n"
        "        SBC     HL, DE\n        JR      NZ, .READ_ERROR"
        in config_source,
        "WEATHER.CFG loading must reject a short DSS read",
    )
    require(
        "CALL    L_READ_EXACT" in loader_source
        and "LD      (L_WIN0_PAGE), A" in loader_source
        and "LD      A, (L_WIN0_PAGE)\n        OUT     (082h), A" in loader_source
        and "LD      DE, 0" in loader_source,
        "loader must verify reads and restore WIN0 after unpacking from WIN3",
    )
    require(
        loader_page_loop.index("CALL    L_READ_EXACT\n        JP      C, L_FAIL")
        < loader_page_loop.index("LD      A, (L_DEST_PAGE)\n        OUT     (082h), A"),
        "WIN0 must keep the DSS RST vectors until packed input has been read",
    )
    require(
        "SBC     HL, DE\n        RET     Z\n        SCF\n        RET" in loader_source,
        "short DSS reads must fail L_READ_EXACT",
    )
    require(
        "LD      HL, 0C000h + WFG_RUNTIME_OFFSET" in loader_source
        and "WFG_RUNTIME_OFFSET       EQU 00100h" in loader_source,
        "ORG #8100 runtime must be loaded at page offset #0100, not #0000",
    )
    psp_copy = (
        "LD      HL, 08000h\n"
        "        LD      DE, 0C000h\n"
        "        LD      BC, WFG_PSP_SIZE\n"
        "        LDIR"
    )
    require(
        psp_copy in loader_source
        and loader_source.index(psp_copy)
        < loader_source.index("LD      HL, 0C000h + WFG_RUNTIME_OFFSET"),
        "replacement WIN2 page must preserve the DSS PSP below ORG #8100",
    )
    # BIOS EMM_FN5 needs a 256-byte destination, so the physical page list is
    # collected in the borrowed config buffer and consumed by the very next
    # call.  Nothing may run between the producer and the consumer.
    require(
        "ASSET_PHYSICAL_PAGES" not in graphics_source + weather_source + loader_source,
        "EMM_FN5 must not write into a short dedicated field: it overruns into "
        "runtime BSS and corrupts the page ports",
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
    attempt_start = weather_source[
        weather_source.index("ATTEMPT_START:") : weather_source.index(
            "CALL    CONFIG_LOAD", weather_source.index("ATTEMPT_START:")
        )
    ]
    require(
        "CALL    GRAPHICS_BEGIN_ATTEMPT" in attempt_start,
        "WEATHER.EXE must enter graphics mode before reading CFG or starting UNET",
    )
    for label in (
        "MSG_GRAPHICS_STAGE",
        "MSG_LOADING_WEATHER",
        "MSG_GRAPHICS_CONNECT",
        "MSG_GRAPHICS_SENDING",
        "MSG_GRAPHICS_SEND",
    ):
        marker = f"LD      HL, {label}"
        marker_pos = source.find(marker)
        require(
            marker_pos >= 0
            and "GRAPHICS_SHOW_STATUS" in source[marker_pos : marker_pos + 120],
            f"graphical progress state is missing: {label}",
        )
    require(
        "GRAPHICS_SHOW_ERROR:" in graphics_ui_source
        and "CALL    GRAPHICS_RESTORE_MODE" in graphics_ui_source
        and "LD      (GRAPHICS_MODE_ACTIVE), A" in graphics_ui_source,
        "graphical errors need a controlled text fallback when GFX/AFNT fails",
    )
    full_message = graphics_ui_source[
        graphics_ui_source.index("GRAPHICS_SHOW_MESSAGE:") : graphics_ui_source.index(
            "; Full-screen help"
        )
    ]
    require(
        "JP      GRAPHICS_DRAW_CLOCK" in full_message,
        "full-screen progress and errors must keep the clock visible",
    )
    require(
        "DSS_WAITKEY" not in graphics_ui_source
        and "DSS_SCANKEY" in graphics_ui_source
        and "GRAPHICS_EVENT_LOOP:" in graphics_ui_source
        and "CP      25" not in graphics_frame_source
        and "GRAPHICS_TIMER_SECOND" in graphics_ui_source
        and "GRAPHICS_TIMER_RESET:" in graphics_ui_source,
        "the graphical forecast loop must scan keys and refresh on the wall-clock timer",
    )
    event_loop = graphics_ui_source[
        graphics_ui_source.index("GRAPHICS_EVENT_LOOP:") : graphics_ui_source.index(
            "GRAPHICS_TIMER_RESET:"
        )
    ]
    require(
        "CALL    GRAPHICS_FRAME_CLOCK" in event_loop
        and "CALL    GRAPHICS_DRAW_CLOCK" not in event_loop
        and "CP      25" not in graphics_frame_source
        and graphics_frame_source.count("CALL    GRAPHICS_DRAW_CLOCK") == 1,
        "the clock should sample DSS time after every interrupt wakeup",
    )
    require(
        ".FRAME: EI\n        HALT" in event_loop
        and "GRAPHICS_IDLE" not in graphics_ui_source,
        "the graphics loop must use EI/HALT with RTC checks, not busy polling",
    )
    require(
        "GRAPHICS_LAST_SECOND" in graphics_frame_source
        and "JR      Z, .FRAME" in event_loop,
        "automatic refresh must advance from DSS wall-clock seconds",
    )
    require(
        "GRAPHICS_DRAW_REFRESH:" in graphics_ui_source
        and "GRAPHICS_DATA_RECT" in graphics_ui_source
        and "CALL    GRAPHICS_CLEAR\n" not in graphics_ui_source[
            graphics_ui_source.index("GRAPHICS_DRAW_REFRESH:") : graphics_ui_source.index(
                "GRAPHICS_DRAW_CLOCK:"
            )
        ],
        "periodic forecast rendering must clear only the data rectangle",
    )
    require(
        "DSS_SYSTIME" in dss_source
        and "HH:MM:SS" in (ROOT / "README.md").read_text(encoding="utf-8")
        and "Usage: WEATHER [minutes]" in loader_source
        and "WFG_RUNTIME_INTERVAL" in loader_source
        and "LD      HL, 5                    ; loader-patched refresh interval"
        in weather_source,
        "graphics clock and loader interval handoff are missing",
    )
    interval_source = (ROOT / "src/interval.asm").read_text(encoding="utf-8")
    require(
        "PUSH    IX\n        POP     HL" in interval_source
        and "LD      HL, 08003h" not in interval_source,
        "CLI must use DSS entry IX; hardcoded #8003 ignores arguments on classic DSS",
    )
    wx1_source = (ROOT / "src" / "wx1.asm").read_text(encoding="utf-8")
    wx1_commit = wx1_source[
        wx1_source.index("WX1_PARSE_OK_DOT:") : wx1_source.index(
            "WX1_PARSE_SERVICE_CODE:"
        )
    ]
    wx1_reset = wx1_source[
        wx1_source.index("WX1_RESET:") : wx1_source.index("; HL=data, BC=size.")
    ]
    require(
        "LD      HL, WX1_STAGE_MODEL\n        LD      DE, WX1_MODEL\n"
        "        LD      BC, WM_MODEL_SIZE\n        LDIR" in wx1_commit
        and "IFNDEF WEATHER_GRAPHICS\n        LD      (WX1_MODEL + WM_VALID), A\n"
        "        ENDIF" in wx1_reset,
        "WX1 failures must leave the last committed forecast model untouched",
    )
    retry_error_labels = (
        "ERROR_CONFIG:",
        "ERROR_CONFIG_FILE:",
        "ERROR_UNETLD:",
        "ERROR_TCP_CAP:",
        "ERROR_CALL:",
        "ERROR_UNET_STATUS:",
        "ERROR_NETSTART:",
        "ERROR_TRANSPORT:",
        "ERROR_SERVICE:",
        "ERROR_WX1:",
        "ERROR_GRAPHICS_RENDER:",
        "ERROR_GRAPHICS_BOOT:",
    )
    retry_error_end = weather_source.index("PRINT_CONFIG_HINT:")
    for index, label in enumerate(retry_error_labels):
        start = weather_source.index(label)
        end = (
            weather_source.index(retry_error_labels[index + 1])
            if index + 1 < len(retry_error_labels)
            else retry_error_end
        )
        block = weather_source[start:end]
        require(
            "LD      (WX1_MODEL" not in block
            and "LD      (GRAPHICS_SHOWN)" not in block,
            f"{label[:-1]} must preserve the committed forecast and shown flag",
        )
    status_update = graphics_ui_source[
        graphics_ui_source.index("GRAPHICS_SHOW_STATUS:") : graphics_ui_source.index(
            "GRAPHICS_SHOW_ERROR:"
        )
    ]
    require(
        "CALL    GRAPHICS_CLEAR_STATUS" in status_update
        and "CALL    GRAPHICS_CLEAR\n" not in status_update
        and "LD      A, (GRAPHICS_SHOWN)" in status_update
        and "JP      Z, GRAPHICS_SHOW_STATUS_SCREEN" in status_update
        and "GRAPHICS_SHOW_STATUS_SCREEN" in graphics_ui_source,
        "initial progress must reuse the cleared centered line, while refresh "
        "progress redraws only the local status band",
    )
    require(
        "LD      DE, GRAPHICS_STATUS_RECT\n        LD      B, GFX_FILL_RECT"
        in graphics_ui_source,
        "the local status update must use GFX320 fill-rect acceleration",
    )
    footer_source = graphics_ui_source[
        graphics_ui_source.index("GRAPHICS_DRAW_FOOTER:") : graphics_ui_source.index(
            "; Periodic refresh"
        )
    ]
    require(
        "DB      240                     ; y" in graphics_ui_source
        and "DW      224" in graphics_ui_source[
            graphics_ui_source.index("GRAPHICS_DATA_RECT:") : graphics_ui_source.index(
                "DAY_ICON_X:"
            )
        ]
        and "MSG_GRAPHICS_HINT" not in footer_source,
        "progress, errors and the key hint must share the one bottom status row",
    )
    require(
        ".FAIL_GFX:\n        LD      HL, (GFX_HANDLE)\n        CALL    LIBMAN.l_free"
        in graphics_ui_source,
        "a partial GFX320/AFNT320 load must release the GFX libman handle",
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
        "LD      HL, MSG_CELSIUS\n        CALL    GRAPHICS_BUFFER_APPEND"
        in graphics_ui_source
        and "LD      IX, 161" not in graphics_ui_source,
        "the Celsius unit must be appended to the formatted temperature",
    )
    for token in (
        "GRAPHICS_BUFFER_APPEND_DATE_TIME",
        "GRAPHICS_WMO_DESCRIPTION",
        "WC_APPARENT",
        "WC_HUMIDITY",
        "WC_WIND",
        "WC_DIRECTION",
        "WD_PRECIPITATION",
        "GRAPHICS_FORMAT_DAY_LABEL",
        "MSG_GRAPHICS_BACKEND_PREFIX",
        "GRAPHICS_SHOW_HELP",
        "MSG_GRAPHICS_HELP_VERSION",
        "MSG_GRAPHICS_HELP_AUTO",
        "MSG_GRAPHICS_HELP_BACKEND_OPEN",
        "MSG_GRAPHICS_HELP_BACKEND_CLOSE",
        "LD      HL, UNETLD.NET_TAG",
        "CP      3Bh",
    ):
        require(token in graphics_ui_source, f"final graphical layout is missing: {token}")
    help_source = graphics_ui_source[
        graphics_ui_source.index("GRAPHICS_SHOW_HELP:") : graphics_ui_source.index(
            "GRAPHICS_WAIT_KEY:"
        )
    ]
    require(
        help_source.count("CALL    GRAPHICS_FADE_OUT") == 2
        and help_source.count("CALL    GRAPHICS_FADE_IN") == 1
        and "JP      GRAPHICS_FADE_IN" in help_source
        and "CALL    GRAPHICS_DRAW_CLOCK" in help_source
        and "LD      HL, (GRAPHICS_LAST_MESSAGE)" in help_source
        and "CALL    GRAPHICS_SHOW_MESSAGE" in help_source
        and "CALL    GRAPHICS_PRINT_STATUS" in help_source,
        "help must pause refresh and restore the exact prior status or error",
    )
    wait_key = graphics_ui_source[
        graphics_ui_source.index("GRAPHICS_WAIT_KEY:") : graphics_ui_source.index(
            "GRAPHICS_EVENT_LOOP:"
        )
    ]
    require(
        ".WAIT:  EI\n        HALT" in wait_key,
        "help must use EI/HALT while updating the clock",
    )
    require(
        "CALL    GRAPHICS_FRAME_CLOCK" in wait_key
        and "GRAPHICS_TIMER_SECOND" not in wait_key,
        "help must keep the clock live while pausing the refresh countdown",
    )
    require(
        "Часы" in message_catalogue["MSG_GRAPHICS_HELP_AUTO"]
        and "автообновление" in message_catalogue["MSG_GRAPHICS_HELP_AUTO"]
        and "Сбой" in message_catalogue["MSG_GRAPHICS_HELP_RETURN"]
        and "клавиша" in message_catalogue["MSG_GRAPHICS_HELP_BACK"]
        and "1..1440" in message_catalogue["MSG_GRAPHICS_HELP_2"]
        and "2:5030/1997.10" in distribution_readme,
        "help must describe the clock, refresh retention and WEATHER N syntax",
    )
    require(
        "LD      IX, 276" in graphics_ui_source
        and "LD      A, 0FFh" in graphics_clock_source
        and "CP      '1'" in graphics_clock_source,
        "the proportional-font clock must have a fixed width at the right edge",
    )
    require(
        "LD      HL, WX1_MODEL + WM_DAYS\n"
        "        LD      (GRAPHICS_TODAY_MODEL_PTR), HL\n"
        "        LD      DE, WM_DAY_SIZE\n"
        "        ADD     HL, DE\n"
        "        LD      (GRAPHICS_DAY_BASE), HL" in graphics_ui_source,
        "the first daily record must feed the current block, not a future card",
    )
    require("ANTONFNT" not in source, "runtime must not reference legacy ANTONFNT")
    require(
        "ASSERT  UNETLD.STATE_SIZE = 315" in source,
        "compact UNETLD state must reserve the complete 315-byte block",
    )
    require(
        "ASSERT  STACK_TOP <= 0BF80h" in weather_source,
        "WIN2 layout must retain at least #80 bytes above the stack",
    )
    require(
        "CALL    GRAPHICS_REUSE_UNET\n        JP      C, ERROR_CONFIG\n"
        "        JP      Z, UNET_READY" in weather_source
        and "CALL    UNETLD.SELECT\n        RET     C\n.LOAD:" in graphics_ui_source,
        "graphics backend replacement must propagate a repeated SELECT failure",
    )


def check_graphics_exe() -> None:
    data = (BUILD / "WEATHER.EXE").read_bytes()
    require(data[:3] == b"EXE" and data[3] == 1, "WEATHER.EXE header is invalid")
    loader_size = struct.unpack_from("<H", data, 8)[0]
    require(loader_size > 0, "WEATHER.EXE must be preload-enabled")
    tail = 0x200 + loader_size
    require(data[tail:tail + 4] == b"WFG2", "graphics manifest is missing")
    version, count, size = struct.unpack_from("<BBH", data, tail + 4)
    require((version, count, size) == (2, 5, 0x4000), "graphics manifest has invalid geometry")
    runtime_size = struct.unpack_from("<H", data, tail + 10)[0]
    sizes = struct.unpack_from("<5H", data, tail + 14)
    require(0 < runtime_size <= 0x3F00, "resident graphics runtime has invalid size")
    runtime = (BUILD / "WEATHER.RUNTIME").read_bytes()
    require(runtime_size == len(runtime), "WFG2 runtime size differs from WEATHER.RUNTIME")
    require(
        data[tail + 24:tail + 24 + runtime_size] == runtime,
        "WFG2 runtime payload differs from WEATHER.RUNTIME",
    )
    require(all(0 < size <= 0x4000 for size in sizes), "packed graphic page has invalid size")
    require(len(data) == tail + 24 + runtime_size + sum(sizes), "manifest does not describe WEATHER.EXE tail")


def check_zip_if_present() -> None:
    archive = ROOT / "distr/weather-forecast.zip"
    if not archive.exists():
        return
    with zipfile.ZipFile(archive) as package:
        names = sorted(package.namelist())
        sample = package.read("WEATHER.SMP")
        for name, expected_hash in EXPECTED_DLLS.items():
            digest = hashlib.sha256(package.read(name)).hexdigest()
            require(digest == expected_hash, f"{name} in ZIP differs from the core manifest")
    require(
        all("/" not in name and len(name.split(".")[0]) <= 8 and len(name.rsplit(".", 1)[-1]) <= 3 for name in names),
        f"ZIP contains a directory or a non-8.3 name: {names}",
    )
    require(
        names == sorted(["AFNT320.DLL", "GFX320.DLL", "README.TXT", "WEATHER.EXE", "WEATHER.SMP", "WEATHERC.EXE", *EXPECTED_DLLS]),
        f"unexpected ZIP contents: {names}",
    )
    require(
        "WEATHER.CFG" not in names
        and sample == (ROOT / "resources/WEATHER.CFG.sample").read_bytes(),
        "ZIP must contain the untouched WEATHER.SMP template, never an active WEATHER.CFG",
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
