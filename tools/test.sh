#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"

"$script_dir/check_deps.py" --check-clean
"$script_dir/test_project.py"
"$script_dir/run_z80_tests.sh"

echo "All stage 2 host tests passed."
