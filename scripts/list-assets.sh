#!/usr/bin/env bash

set -euo pipefail

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
asset_dir=$plugin_root/assets

mkdir -p "$asset_dir"

find "$asset_dir" -maxdepth 1 -type f \( \
  -iname '*.mp4' -o \
  -iname '*.webm' -o \
  -iname '*.mkv' -o \
  -iname '*.mov' -o \
  -iname '*.m4v' \
\) -print | sort -f
