#!/usr/bin/env bash

# Single source of truth for all runtime artifacts.
DIST_NAME="${DIST_NAME:-weather-forecast}"
DIST_FILES=(
  "WEATHERC.EXE"
  "UNETESP.DLL"
  "UNETRTL.DLL"
  "README.TXT"
)
