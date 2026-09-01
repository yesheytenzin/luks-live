#!/usr/bin/env bash
set -euo pipefail
video=${1:-}
[[ -n $video && -f $video && ! -L $video ]] || exit 0
fps_str=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=noprint_wrappers=1:nokey=1 "$video" 2>/dev/null || true)
if [[ -z $fps_str || $fps_str == "0/0" ]]; then
  fps_str=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$video" 2>/dev/null || true)
fi
fps=0
if [[ $fps_str =~ ^([0-9]+)/([0-9]+)$ ]]; then
  num=${BASH_REMATCH[1]}
  den=${BASH_REMATCH[2]}
  if (( den != 0 )); then
    fps=$(awk -v n="$num" -v d="$den" 'BEGIN { printf "%.0f", n/d }')
  fi
elif [[ $fps_str =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  fps=$(awk -v s="$fps_str" 'BEGIN { printf "%.0f", s }')
fi
if ! [[ $fps =~ ^[0-9]+$ ]] || (( fps == 0 )); then
  exit 0
fi
if (( fps < 8 )); then fps=8; fi
if (( fps > 20 )); then fps=20; fi
printf '%s\n' "$fps"
