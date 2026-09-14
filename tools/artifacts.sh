#!/usr/bin/env bash

# The core manifest is the source of truth for the complete UNET DLL set.
DIST_NAME="${DIST_NAME:-weather-forecast}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNET_MANIFEST="$repo_root/extern/unet_libs_asm/extern/core/dll/manifest.json"
UNET_DLLS=()
unet_dll_list="$(python3 -c '
import json, re, sys
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
names = sorted(manifest)
pattern = re.compile(r"UNET[A-Z0-9]{3,4}\.DLL")
if not names or any(pattern.fullmatch(name) is None for name in names):
    raise SystemExit("invalid or empty UNET DLL manifest")
if any(manifest[name].get("tag") != name[4:-4] for name in names):
    raise SystemExit("UNET DLL manifest tag/name mismatch")
print("\n".join(names))
' "$UNET_MANIFEST")"
while IFS= read -r dll; do
  UNET_DLLS+=("$dll")
done <<< "$unet_dll_list"
DIST_FILES=(
  "WEATHER.EXE"
  "WEATHERC.EXE"
  "AFNT320.DLL"
  "GFX320.DLL"
  "${UNET_DLLS[@]}"
  "WEATHER.SMP"
  "README.TXT"
)
