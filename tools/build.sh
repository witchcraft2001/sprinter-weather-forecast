#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
build_dir="$repo_root/build"

if ! command -v sjasmplus >/dev/null 2>&1; then
  echo "Error: sjasmplus is not installed or not in PATH" >&2
  exit 1
fi

"$script_dir/check_deps.py"

mkdir -p "$build_dir/generated"
"$script_dir/gen_messages.py" \
  "$repo_root/resources/messages.json" \
  "$build_dir/generated/messages.inc"

cp "$repo_root/extern/esp_net/UNETESP.DLL" "$build_dir/UNETESP.DLL"
cp "$repo_root/extern/rtl_net/UNETRTL.DLL" "$build_dir/UNETRTL.DLL"

sjasmplus --nologo --fullpath \
  -I "$repo_root/extern/esp_net/src/include" \
  -I "$repo_root/extern/libman/libman" \
  -I "$build_dir/generated" \
  --lst="$build_dir/WEATHER.lst" \
  --sym="$build_dir/WEATHER.sym" \
  --raw="$build_dir/WEATHER.EXE" \
  "$repo_root/src/weather.asm"

"$script_dir/check_exe.py" \
  "$build_dir/WEATHER.EXE" \
  "$build_dir/WEATHER.sym"
