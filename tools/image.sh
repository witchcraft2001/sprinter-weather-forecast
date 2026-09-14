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
for dll in "${UNET_DLLS[@]}"; do
  cp "$repo_root/build/$dll" "$stage/$dll"
done
cp "$repo_root/resources/WEATHER.CFG.sample" "$stage/WEATHER.SMP"
sed 's/$/'$'\r''/' "$repo_root/resources/README.ru.txt" |
  iconv -f UTF-8 -t CP866 > "$stage/README.TXT"

rm -f "$image"
mformat -C -f 1440 -v WEATHER -i "$image" ::
for artifact in "${DIST_FILES[@]}"; do
  mcopy -o -i "$image" "$stage/$artifact" "::$artifact"
done

if [[ "${WEATHER_DEBUG_CFG:-0}" == "1" ]]; then
  # The stable template leaves LOCATION commented out; the debug image needs a
  # fixed place so screenshots stay comparable between runs.
  cp "$repo_root/resources/WEATHER.CFG.debug" "$stage/WEATHER.CFG"
  mcopy -o -i "$image" "$stage/WEATHER.CFG" ::WEATHER.CFG
  # GFX320's own prebuilt reference consumer.  It enters video mode #81 exactly
  # as WEATHER.EXE does, but without its PRELOAD loader. Running it separates
  # a general #81 failure from the loader/runtime handoff. Debug image only:
  # the stable artifact's contents are fixed.
  cp "$repo_root/extern/sprinter-libs/gfx320/GFX320.EXE" "$stage/GFXTEST.EXE"
  mcopy -o -i "$image" "$stage/GFXTEST.EXE" ::GFXTEST.EXE
fi

listing="$(mdir -b -i "$image" ::)"
actual_files="$(sed 's#^::/##' <<< "$listing" | sort)"
expected_artifacts=("${DIST_FILES[@]}")
if [[ "${WEATHER_DEBUG_CFG:-0}" == "1" ]]; then
  expected_artifacts+=("WEATHER.CFG" "GFXTEST.EXE")
fi
expected_files="$(printf '%s\n' "${expected_artifacts[@]}" | sort)"
if [[ "$actual_files" != "$expected_files" ]]; then
  echo "Error: FAT12 file set differs from the distribution manifest" >&2
  diff -u <(printf '%s\n' "$expected_files") <(printf '%s\n' "$actual_files") >&2 || true
  exit 1
fi
for artifact in "${DIST_FILES[@]}"; do
  if ! grep -q "/$artifact$" <<< "$listing"; then
    echo "Error: $artifact is missing from FAT12 image" >&2
    exit 1
  fi
done

verify_dir="$repo_root/build/image/verify"
mkdir -p "$verify_dir"
for dll in "${UNET_DLLS[@]}"; do
  mcopy -o -i "$image" "::$dll" "$verify_dir/$dll"
  if ! cmp -s "$repo_root/build/$dll" "$verify_dir/$dll"; then
    echo "Error: $dll in FAT12 image differs from the core manifest copy" >&2
    exit 1
  fi
done
mcopy -o -i "$image" ::WEATHER.SMP "$verify_dir/WEATHER.SMP"
if ! cmp -s "$repo_root/resources/WEATHER.CFG.sample" "$verify_dir/WEATHER.SMP"; then
  echo "Error: WEATHER.SMP in FAT12 image differs from the source template" >&2
  exit 1
fi

echo "Created FAT12 image: $image"
