#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: prepare.sh <video> <duration-ms> <fps> <width> <height> <entry-x-milli> <entry-y-milli> <audio:0|1> <volume-percent>" >&2
  exit 2
}

(( $# == 9 )) || usage

source_video=$1
duration_ms=$2
fps=$3
width=$4
height=$5
entry_x_milli=$6
entry_y_milli=$7
audio_requested=$8
volume_percent=$9

[[ -f $source_video && ! -L $source_video ]] || { echo "Video is not a regular file: $source_video" >&2; exit 1; }
[[ $duration_ms =~ ^[0-9]+$ ]] && (( duration_ms >= 1000 && duration_ms <= 10000 )) || { echo "Duration must be 1000-10000 ms" >&2; exit 1; }
[[ $fps =~ ^[0-9]+$ ]] && (( fps >= 8 && fps <= 20 )) || { echo "FPS must be 8-20" >&2; exit 1; }
[[ $width =~ ^[0-9]+$ ]] && (( width >= 640 && width <= 1920 )) || { echo "Width must be 640-1920" >&2; exit 1; }
[[ $height =~ ^[0-9]+$ ]] && (( height >= 360 && height <= 1080 )) || { echo "Height must be 360-1080" >&2; exit 1; }
[[ $entry_x_milli =~ ^[0-9]+$ ]] && (( entry_x_milli <= 1000 )) || { echo "Entry X must be 0-1000" >&2; exit 1; }
[[ $entry_y_milli =~ ^[0-9]+$ ]] && (( entry_y_milli <= 1000 )) || { echo "Entry Y must be 0-1000" >&2; exit 1; }
[[ $audio_requested == 0 || $audio_requested == 1 ]] || usage
[[ $volume_percent =~ ^[0-9]+$ ]] && (( volume_percent <= 100 )) || { echo "Volume must be 0-100" >&2; exit 1; }

for command_name in ffmpeg ffprobe; do
  command -v "$command_name" >/dev/null 2>&1 || { echo "Missing required command: $command_name" >&2; exit 1; }
done

ffprobe -v error -select_streams v:0 -show_entries stream=index -of csv=p=0 "$source_video" | grep -q . || {
  echo "The selected file has no readable video stream" >&2
  exit 1
}

cache_root=${XDG_CACHE_HOME:-$HOME/.cache}/omaliveboot
prepared_dir=$cache_root/prepared
staging_dir=$cache_root/.prepared.$$
trap 'rm -rf -- "$staging_dir"' EXIT

mkdir -p "$cache_root"
rm -rf -- "$staging_dir"
mkdir -p "$staging_dir/frames"

duration_seconds=$(awk -v ms="$duration_ms" 'BEGIN { printf "%.3f", ms / 1000 }')

ffmpeg -hide_banner -loglevel error -y -i "$source_video" \
  -t "$duration_seconds" \
  -vf "fps=$fps,scale=$width:$height:force_original_aspect_ratio=increase,crop=$width:$height" \
  -start_number 0 "$staging_dir/frames/%d.png"

shopt -s nullglob
frames=("$staging_dir"/frames/*.png)
frame_count=${#frames[@]}
(( frame_count > 0 && frame_count <= 200 )) || { echo "Frame extraction produced an invalid frame count: $frame_count" >&2; exit 1; }

intro_duration=$duration_seconds
audio_enabled=0
audio_device=

if [[ $audio_requested == 1 ]] && ffprobe -v error -select_streams a:0 -show_entries stream=index -of csv=p=0 "$source_video" | grep -q .; then
  audio_device="$($(dirname "$0")/audio-device.sh || true)"
  if [[ $audio_device =~ ^hw:[A-Za-z0-9_-]+,[0-9]+$ ]]; then
    volume_gain=$(awk -v percent="$volume_percent" 'BEGIN { printf "%.2f", percent / 100 }')
    ffmpeg -hide_banner -loglevel error -y -i "$source_video" \
      -vn -t "$intro_duration" -af "volume=$volume_gain,apad" \
      -ac 2 -ar 48000 -c:a pcm_s16le "$staging_dir/intro.wav"
    audio_enabled=1
  fi
fi

cat >"$staging_dir/metadata" <<EOF
FRAME_COUNT=$frame_count
FPS=$fps
INTRO_DURATION=$intro_duration
WIDTH=$width
HEIGHT=$height
ENTRY_X_MILLI=$entry_x_milli
ENTRY_Y_MILLI=$entry_y_milli
AUDIO_ENABLED=$audio_enabled
AUDIO_DEVICE=$audio_device
EOF

payload_size=$(du -sb "$staging_dir" | cut -f1)
(( payload_size <= 134217728 )) || { echo "Prepared boot media exceeds the 128 MiB limit" >&2; exit 1; }

rm -rf -- "$prepared_dir"
mv -- "$staging_dir" "$prepared_dir"
trap - EXIT

printf 'Prepared %d frames at %d FPS (%s seconds)\n' "$frame_count" "$fps" "$intro_duration"
if [[ $audio_requested == 1 && $audio_enabled == 0 ]]; then
  printf 'Sound disabled: no audio stream or built-in analog ALSA device was found\n'
elif [[ $audio_enabled == 1 ]]; then
  printf 'Sound prepared for %s\n' "$audio_device"
fi
