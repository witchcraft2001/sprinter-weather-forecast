#!/usr/bin/env bash

# Single source of truth for all runtime artifacts.
DIST_NAME="${DIST_NAME:-weather-forecast}"
DIST_FILES=(
  "WEATHER.EXE"
  "WEATHERC.EXE"
  "AFNT320.DLL"
  "GFX320.DLL"
  "UNETESP.DLL"
  "UNETRTL.DLL"
  "README.TXT"
)
