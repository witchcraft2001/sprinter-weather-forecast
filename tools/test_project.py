#!/usr/bin/env python3
"""Host-side artifact and source contract checks."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
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
    for name, expected_hash in EXPECTED_DLLS.items():
        data = (BUILD / name).read_bytes()
        require(hashlib.sha256(data).hexdigest() == expected_hash, f"{name} changed while staging")


def check_messages() -> None:
    catalogue = json.loads((ROOT / "resources/messages.json").read_text(encoding="utf-8"))
    generated = (BUILD / "generated/messages.inc").read_text(encoding="ascii")
    for label, value in catalogue.items():
        require(f"{label}:" in generated, f"generated message {label} is missing")
        value.encode("cp866")
    require("AFNT320" not in generated, "stage 1 must not load AFNT320")


def check_source_contract() -> None:
    source = "\n".join(
        (ROOT / "src" / name).read_text(encoding="utf-8")
        for name in ("weather.asm", "config.asm", "wx1.asm", "text_ui.asm", "transport.asm")
    )
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
    require("AFNT320" not in source, "text MVP must not load the graphics library")
    require("ANTONFNT" not in source, "text MVP must not reference ANTONFNT")
    require(
        "ENV_VALUE_SIZE  EQU 256" in source,
        "ENV_GET buffer must cover DSS's maximum environment value",
    )


def check_zip_if_present() -> None:
    archive = ROOT / "distr/weather-forecast.zip"
    if not archive.exists():
        return
    with zipfile.ZipFile(archive) as package:
        names = sorted(package.namelist())
    require(
        names == ["README.TXT", "UNETESP.DLL", "UNETRTL.DLL", "WEATHER.EXE"],
        f"unexpected ZIP contents: {names}",
    )


def main() -> int:
    check_runtime_files()
    check_messages()
    check_source_contract()
    check_zip_if_present()
    print("Host artifact tests: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
