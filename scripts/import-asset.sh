#!/usr/bin/env bash

set -euo pipefail

(( $# == 1 )) || { echo "Usage: import-asset.sh <video>" >&2; exit 2; }

source_video=$1
plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
asset_dir=$plugin_root/assets

[[ -f $source_video && ! -L $source_video ]] || { echo "Video is not a regular file: $source_video" >&2; exit 1; }

case ${source_video##*.} in
  mp4 | MP4 | webm | WEBM | mkv | MKV | mov | MOV | m4v | M4V) ;;
  *) echo "Unsupported video container; use MP4, WebM, MKV, MOV, or M4V" >&2; exit 1 ;;
esac

size=$(stat -c %s -- "$source_video")
(( size > 0 && size <= 536870912 )) || { echo "Live wallpaper must be smaller than 512 MiB" >&2; exit 1; }

mkdir -p "$asset_dir"
source_video=$(realpath -e -- "$source_video")
asset_dir=$(realpath -e -- "$asset_dir")

if [[ ${source_video%/*} == "$asset_dir" ]]; then
  printf '%s\n' "$source_video"
  exit 0
fi

filename=${source_video##*/}
destination=$asset_dir/$filename

if [[ -e $destination && ! $source_video -ef $destination ]]; then
  stem=${filename%.*}
  extension=${filename##*.}
  destination=$asset_dir/${stem}-$(date +%Y%m%d-%H%M%S).$extension
fi

install -m 0644 -- "$source_video" "$destination"
printf '%s\n' "$destination"
