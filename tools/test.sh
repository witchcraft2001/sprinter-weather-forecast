#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"

"$script_dir/check_deps.py" --check-clean
"$script_dir/test_project.py"

echo "All stage 1 tests passed."
