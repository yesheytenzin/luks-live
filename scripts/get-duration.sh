#!/usr/bin/env bash
set -euo pipefail
video=${1:-}
[[ -n $video && -f $video && ! -L $video ]] || exit 0
# ffprobe duration in seconds, convert to ms
dur=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video" 2>/dev/null || true)
if [[ -z $dur || $dur == "N/A" ]]; then
  # fallback to stream duration
  dur=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 "$video" 2>/dev/null || true)
fi
if [[ -z $dur || $dur == "N/A" ]]; then exit 0; fi
# awk to ms, rounded
ms=$(awk -v d="$dur" 'BEGIN { printf "%.0f", d*1000 }')
if ! [[ $ms =~ ^[0-9]+$ ]] || (( ms == 0 )); then exit 0; fi
printf '%s\n' "$ms"
