#!/usr/bin/env python3
"""Generate sjasmplus CP866 byte arrays from the UTF-8 message catalogue."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re


LABEL_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")


def byte_lines(label: str, value: str) -> list[str]:
    encoded = value.encode("cp866") + b"\0"
    result = [f"{label}:"]
    for offset in range(0, len(encoded), 16):
        chunk = encoded[offset : offset + 16]
        values = ", ".join(f"0{byte:02X}h" for byte in chunk)
        result.append(f"        DB      {values}")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("catalogue", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    catalogue = json.loads(args.catalogue.read_text(encoding="utf-8"))
    if not isinstance(catalogue, dict):
        raise SystemExit("message catalogue must be a JSON object")

    output = [
        "; Generated from resources/messages.json. Do not edit.",
        "",
    ]
    for label, value in catalogue.items():
        if not isinstance(label, str) or not LABEL_RE.fullmatch(label):
            raise SystemExit(f"invalid assembler label: {label!r}")
        if not isinstance(value, str) or "\0" in value:
            raise SystemExit(f"invalid message value for {label}")
        output.extend(byte_lines(label, value))
        output.append("")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(output), encoding="ascii")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
