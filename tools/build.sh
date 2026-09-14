#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
build_dir="$repo_root/build"
target="${1:-all}"
console_name="WEATHERC"
graphics_name="WEATHER"
source "$script_dir/artifacts.sh"

if ! command -v sjasmplus >/dev/null 2>&1; then
  echo "Error: sjasmplus is not installed or not in PATH" >&2
  exit 1
fi

"$script_dir/check_deps.py"

mkdir -p "$build_dir/generated"
"$script_dir/gen_messages.py" \
  "$repo_root/resources/messages.json" \
  "$build_dir/generated/messages.inc"

find "$build_dir" -maxdepth 1 -type f -name 'UNET*.DLL' -delete
for dll in "${UNET_DLLS[@]}"; do
  cp "$repo_root/extern/unet_libs_asm/extern/core/dll/$dll" "$build_dir/$dll"
done
cp "$repo_root/extern/sprinter-libs/afnt320/AFNT320.DLL" "$build_dir/AFNT320.DLL"
cp "$repo_root/extern/sprinter-libs/gfx320/GFX320.DLL" "$build_dir/GFX320.DLL"

asm_defines=()
if [[ "${WEATHER_DEBUG_RAW:-0}" == "1" ]]; then
  asm_defines+=("-DWEATHER_DEBUG_RAW=1")
fi

build_console() {
  sjasmplus --nologo --fullpath "${asm_defines[@]}" \
    -I "$repo_root/extern/unet_libs_asm/include" \
    -I "$repo_root/extern/unet_libs_asm/extern/core/bindings/asm" \
    -I "$repo_root/extern/unet_libs_asm/extern/libman/libman" \
    -I "$build_dir/generated" --lst="$build_dir/$console_name.lst" \
    --sym="$build_dir/$console_name.sym" --raw="$build_dir/$console_name.EXE" \
    "$repo_root/src/weatherc.asm"
  "$script_dir/check_exe.py" "$build_dir/$console_name.EXE" "$build_dir/$console_name.sym"
}

build_graphics() {
  python3 "$script_dir/build_assets.py"
  python3 "$script_dir/pack_hrust.py"
  sjasmplus --nologo --fullpath "${asm_defines[@]}" -DWEATHER_RUNTIME=1 \
    -I "$repo_root/extern/unet_libs_asm/include" \
    -I "$repo_root/extern/unet_libs_asm/extern/core/bindings/asm" \
    -I "$repo_root/extern/unet_libs_asm/extern/libman/libman" \
    -I "$repo_root/extern/sprinter-libs/gfx320" -I "$build_dir/generated/weather_assets" \
    --lst="$build_dir/$graphics_name.runtime.lst" --sym="$build_dir/$graphics_name.runtime.sym" \
    --raw="$build_dir/$graphics_name.RUNTIME" "$repo_root/src/weather.asm"
  sjasmplus --nologo --fullpath \
    -I "$repo_root/src" \
    --lst="$build_dir/$graphics_name.loader.lst" --sym="$build_dir/$graphics_name.loader.sym" \
    --raw="$build_dir/$graphics_name.LOADER.EXE" "$repo_root/src/weather_loader.asm"
  python3 "$script_dir/pack_weather_exe.py" "$build_dir/$graphics_name.LOADER.EXE" \
    "$build_dir/$graphics_name.RUNTIME" "$build_dir/generated/weather_assets" \
    "$build_dir/$graphics_name.EXE"
  "$script_dir/check_exe.py" "$build_dir/$graphics_name.EXE" "$build_dir/$graphics_name.loader.sym" \
    "$build_dir/$graphics_name.runtime.sym"
}

case "$target" in
  weatherc) build_console ;;
  weather) build_graphics ;;
  all) build_console; build_graphics ;;
  *) echo "Usage: $0 [all|weather|weatherc]" >&2; exit 2 ;;
esac
