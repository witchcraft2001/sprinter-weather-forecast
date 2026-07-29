#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

source "$script_dir/artifacts.sh"

if ! command -v zip >/dev/null 2>&1; then
  echo "Error: zip is not installed or not in PATH" >&2
  exit 1
fi
if ! command -v iconv >/dev/null 2>&1; then
  echo "Error: iconv is not installed or not in PATH" >&2
  exit 1
fi

package_root="$repo_root/build/package"
archive="$repo_root/distr/$DIST_NAME.zip"

rm -rf "$package_root"
mkdir -p "$package_root" "$repo_root/distr"

cp "$repo_root/build/WEATHERC.EXE" "$package_root/WEATHERC.EXE"
cp "$repo_root/build/UNETESP.DLL" "$package_root/UNETESP.DLL"
cp "$repo_root/build/UNETRTL.DLL" "$package_root/UNETRTL.DLL"
sed 's/$/'$'\r''/' "$repo_root/resources/README.ru.txt" |
  iconv -f UTF-8 -t CP866 > "$package_root/README.TXT"

rm -f "$archive"
(
  cd "$package_root"
  zip -q "$archive" "${DIST_FILES[@]}"
)

echo "Created $archive"
