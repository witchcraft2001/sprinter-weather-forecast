# Weather Graphics Sources

These PNG files are the editable source of every icon embedded in
`WEATHER.EXE`. The build reads them directly; files under
`build/generated/weather_assets/` are generated output and must not be edited.

## Layout

- `weather/64/` — 15 current-condition icons, exactly 64×64 pixels.
- `weather/32/` — 15 independently editable forecast icons, exactly 32×32.
- `ui/` — four 16×16 auxiliary icons.

The numeric filename prefix is the internal icon-family index and must not be
changed. Large and small directories must keep the same names.

## Editing Rules

Use an indexed-pixel editor such as Aseprite, GrafX2, or GIMP. Each source PNG
already contains the complete project palette.

- Keep the canvas dimensions unchanged.
- Keep hard pixel edges; do not resample or apply antialiasing.
- Transparent pixels use palette index `255` (`0xFF`).
- Opaque pixels must use colours already present in the embedded palette.
- Alpha must be either fully transparent or fully opaque.
- Save as non-interlaced indexed, RGB, or RGBA PNG.

The 32×32 files are not regenerated from their 64×64 counterparts during a
normal build, so both variants can be retouched for their actual display size.

Run `make weather` after editing. The build reports the exact file and pixel
when it encounters an invalid size, colour, or alpha value.

`python3 tools/build_assets.py --export-defaults --force` restores every PNG to
the original procedural artwork and therefore overwrites manual edits.
