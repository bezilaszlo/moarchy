#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
exec python3 "$repo/scripts/stage-willow.py" "${1:-$repo/..}"
