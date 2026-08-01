#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
build_dir="$repo_root/build/tests"
ticks="${TICKS:-/Users/dmitry/dev/zx/sprinter/z88dk/bin/z88dk-ticks}"

command -v sjasmplus >/dev/null
[[ -x "$ticks" ]] || { echo "Error: z88dk-ticks not found; set TICKS" >&2; exit 1; }
mkdir -p "$build_dir"

bin="$build_dir/t_response.bin"
dump="$build_dir/t_response.out"
sjasmplus --nologo --fullpath -I "$repo_root/src" -I "$repo_root/tests/z80" \
  --raw="$bin" "$repo_root/tests/z80/t_response.asm"
rm -f "$dump"
"$ticks" -pc 0 -counter 5000000 -output "$dump" "$bin" >/dev/null 2>&1 || true
[[ -f "$dump" ]] || { echo "FAIL z80 response harness: no memory dump" >&2; exit 1; }

byte_at_file() { dd if="$1" bs=1 skip="$2" count=1 2>/dev/null | od -An -tu1 | tr -d ' \n'; }
byte_at() { byte_at_file "$dump" "$1"; }
[[ "$(byte_at 57345)" == "165" ]] || { echo "FAIL z80 response harness: incomplete" >&2; exit 1; }
[[ "$(byte_at 57344)" == "0" ]] || {
  echo "FAIL z80 response harness: assertion $(byte_at 57346), failures=$(byte_at 57347)" >&2
  exit 1
}
echo "Z80 response harness: OK"

config_bin="$build_dir/t_config.bin"
config_dump="$build_dir/t_config.out"
sjasmplus --nologo --fullpath -I "$repo_root/src" -I "$repo_root/tests/z80" \
  --raw="$config_bin" "$repo_root/tests/z80/t_config.asm"
rm -f "$config_dump"
"$ticks" -pc 0 -counter 2000000 -output "$config_dump" "$config_bin" >/dev/null 2>&1 || true
[[ -f "$config_dump" ]] || { echo "FAIL z80 config harness: no memory dump" >&2; exit 1; }
[[ "$(byte_at_file "$config_dump" 57345)" == "165" ]] || {
  echo "FAIL z80 config harness: incomplete" >&2
  exit 1
}
[[ "$(byte_at_file "$config_dump" 57344)" == "0" ]] || {
  echo "FAIL z80 config harness: assertion $(byte_at_file "$config_dump" 57346)," \
    "failures=$(byte_at_file "$config_dump" 57347)" >&2
  exit 1
}
echo "Z80 config harness: OK (LF, CRLF, no-EOL and multiline)"

assets="$repo_root/build/generated/weather_assets"
# Regenerate the streams unconditionally: a stale .hst next to modified .bin
# artwork would otherwise look like a depacker regression.
python3 "$repo_root/tools/build_assets.py"
python3 "$repo_root/tools/pack_hrust.py"
hrust_bin="$build_dir/t_hrust.bin"
hrust_dump="$build_dir/t_hrust.out"
sjasmplus --nologo --fullpath -I "$repo_root/src" -I "$assets" \
  --raw="$hrust_bin" "$repo_root/tests/z80/t_hrust.asm"
rm -f "$hrust_dump"
# Five 16 KiB pages plus a per-byte checksum over each of them.
"$ticks" -pc 0 -counter 60000000 -output "$hrust_dump" "$hrust_bin" >/dev/null 2>&1 || true
[[ -f "$hrust_dump" ]] || { echo "FAIL z80 Hrust harness: no memory dump" >&2; exit 1; }
[[ "$(byte_at_file "$hrust_dump" 57345)" == "165" ]] || {
  echo "FAIL z80 Hrust harness: incomplete, reached page $(byte_at_file "$hrust_dump" 57346)" >&2
  exit 1
}
[[ "$(byte_at_file "$hrust_dump" 57344)" == "0" ]] || {
  echo "FAIL z80 Hrust harness: HRUST_DEPACK did not restore SP on page" \
    "$(byte_at_file "$hrust_dump" 57346)" >&2
  exit 1
}
# The harness stores one rolling checksum per unpacked page at #E010; compare
# them with the same checksum taken over the original page images.
python3 - "$assets" "$hrust_dump" <<'PY' || exit 1
import sys
from pathlib import Path

assets, dump = Path(sys.argv[1]), Path(sys.argv[2])
blob = dump.read_bytes()

def checksum(data: bytes) -> int:
    acc = 0
    for byte in data:
        acc = ((acc << 1) | (acc >> 15)) & 0xFFFF
        acc = (acc + byte) & 0xFFFF
    return acc

for index in range(5):
    expected = checksum((assets / f"page{index:02d}.bin").read_bytes())
    offset = 0xE010 + index * 2
    actual = blob[offset] | (blob[offset + 1] << 8)
    if actual != expected:
        print(
            f"FAIL z80 Hrust harness: page{index:02d} unpacked to "
            f"{actual:#06x}, expected {expected:#06x}",
            file=sys.stderr,
        )
        raise SystemExit(1)
PY
echo "Z80 Hrust harness: OK (5 pages, SP and content verified)"
