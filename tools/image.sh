#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

source "$script_dir/artifacts.sh"

for tool in mformat mcopy mdir iconv; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: $tool is not installed or not in PATH" >&2
    exit 1
  fi
done

image="$repo_root/distr/$DIST_NAME.img"
stage="$repo_root/build/image"

rm -rf "$stage"
mkdir -p "$stage" "$repo_root/distr"

cp "$repo_root/build/WEATHER.EXE" "$stage/WEATHER.EXE"
cp "$repo_root/build/WEATHERC.EXE" "$stage/WEATHERC.EXE"
cp "$repo_root/build/AFNT320.DLL" "$stage/AFNT320.DLL"
cp "$repo_root/build/GFX320.DLL" "$stage/GFX320.DLL"
cp "$repo_root/build/UNETESP.DLL" "$stage/UNETESP.DLL"
cp "$repo_root/build/UNETRTL.DLL" "$stage/UNETRTL.DLL"
sed 's/$/'$'\r''/' "$repo_root/resources/README.ru.txt" |
  iconv -f UTF-8 -t CP866 > "$stage/README.TXT"

rm -f "$image"
mformat -C -f 1440 -v WEATHER -i "$image" ::
for artifact in "${DIST_FILES[@]}"; do
  mcopy -o -i "$image" "$stage/$artifact" "::$artifact"
done

if [[ "${WEATHER_DEBUG_CFG:-0}" == "1" ]]; then
  cp "$repo_root/resources/WEATHER.CFG.sample" "$stage/WEATHER.CFG"
  mcopy -o -i "$image" "$stage/WEATHER.CFG" ::WEATHER.CFG
  # GFX320's own prebuilt reference consumer.  It enters video mode #81 exactly
  # as WEATHER.EXE does, but without its PRELOAD loader. Running it separates
  # a general #81 failure from the loader/runtime handoff. Debug image only:
  # the stable artifact's contents are fixed.
  cp "$repo_root/extern/sprinter-libs/gfx320/GFX320.EXE" "$stage/GFXTEST.EXE"
  mcopy -o -i "$image" "$stage/GFXTEST.EXE" ::GFXTEST.EXE
fi

listing="$(mdir -b -i "$image" ::)"
for artifact in "${DIST_FILES[@]}"; do
  if ! grep -q "/$artifact$" <<< "$listing"; then
    echo "Error: $artifact is missing from FAT12 image" >&2
    exit 1
  fi
done

echo "Created FAT12 image: $image"
