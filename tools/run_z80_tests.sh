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

byte_at() { dd if="$dump" bs=1 skip="$1" count=1 2>/dev/null | od -An -tu1 | tr -d ' \n'; }
[[ "$(byte_at 57345)" == "165" ]] || { echo "FAIL z80 response harness: incomplete" >&2; exit 1; }
[[ "$(byte_at 57344)" == "0" ]] || {
  echo "FAIL z80 response harness: assertion $(byte_at 57346), failures=$(byte_at 57347)" >&2
  exit 1
}
echo "Z80 response harness: OK"
