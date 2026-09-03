#!/usr/bin/env bash

set -Eeuo pipefail

THEME_NAME=omaliveboot
THEME_DIR=/usr/share/plymouth/themes/$THEME_NAME
STATE_DIR=/var/lib/omaliveboot
HOOK_INSTALL=/etc/initcpio/install/luks-live
HOOK_RUNTIME=/etc/initcpio/hooks/luks-live
HOOK_CONFIG=/etc/mkinitcpio.conf.d/zz-omaliveboot.conf
SOURCE_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

usage() {
  echo "Usage: install.sh --apply <prepared-directory> | --revert | --validate <prepared-directory>" >&2
  exit 2
}

require_root() {
  (( EUID == 0 )) || { echo "Luks Live installation requires administrator privileges" >&2; exit 1; }
}

rebuild_initramfs() {
  if command -v limine-mkinitcpio >/dev/null 2>&1; then
    limine-mkinitcpio
  else
    mkinitcpio -P
  fi
}

write_hook_config() {
  install -m 0644 "$SOURCE_ROOT/initcpio/zz-omaliveboot.conf" "$HOOK_CONFIG"
}

metadata_value() {
  local key=$1 file=$2
  awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2); exit }' "$file"
}

validate_prepared() {
  local prepared=$1 metadata frame_count fps duration width height x y audio device size index

  metadata=$prepared/metadata

  [[ $prepared == /* && -d $prepared && ! -L $prepared ]] || { echo "Invalid prepared media directory" >&2; return 1; }
  [[ -f $metadata && ! -L $metadata ]] || { echo "Prepared metadata is missing" >&2; return 1; }
  ! find "$prepared" -type l -print -quit | grep -q . || { echo "Prepared media must not contain symbolic links" >&2; return 1; }

  frame_count=$(metadata_value FRAME_COUNT "$metadata")
  fps=$(metadata_value FPS "$metadata")
  duration=$(metadata_value INTRO_DURATION "$metadata")
  width=$(metadata_value WIDTH "$metadata")
  height=$(metadata_value HEIGHT "$metadata")
  x=$(metadata_value ENTRY_X_MILLI "$metadata")
  y=$(metadata_value ENTRY_Y_MILLI "$metadata")
  audio=$(metadata_value AUDIO_ENABLED "$metadata")
  device=$(metadata_value AUDIO_DEVICE "$metadata")

  [[ $frame_count =~ ^[0-9]+$ ]] && (( frame_count >= 1 && frame_count <= 200 ))
  [[ $fps =~ ^[0-9]+$ ]] && (( fps >= 8 && fps <= 30 ))
  [[ $duration =~ ^[0-9]+\.[0-9]{3}$ ]]
  [[ $width =~ ^[0-9]+$ ]] && (( width >= 640 && width <= 1920 ))
  [[ $height =~ ^[0-9]+$ ]] && (( height >= 360 && height <= 1080 ))
  [[ $x =~ ^[0-9]+$ ]] && (( x <= 1000 ))
  [[ $y =~ ^[0-9]+$ ]] && (( y <= 1000 ))
  [[ $audio == 0 || $audio == 1 ]]
  [[ $audio == 0 || $device =~ ^hw:[A-Za-z0-9_-]+,[0-9]+$ ]]

  for ((index = 0; index < frame_count; index++)); do
    [[ -f $prepared/frames/$index.png && ! -L $prepared/frames/$index.png ]] || {
      echo "Prepared frame $index is missing" >&2
      return 1
    }
  done
  [[ $audio == 0 || ( -f $prepared/intro.wav && ! -L $prepared/intro.wav ) ]]

  size=$(du -sb "$prepared" | cut -f1)
  (( size > 0 && size <= 134217728 )) || { echo "Prepared media exceeds the 128 MiB limit" >&2; return 1; }
}

apply_theme() {
  local prepared=$1 metadata stage previous frame_count fps duration x y audio device entry_x entry_y index
  local backup available_kb required_kb had_theme=0 had_install_hook=0 had_runtime_hook=0 had_hook_config=0 had_previous_state=0

  prepared=$(realpath -e -- "$prepared")
  metadata=$prepared/metadata
  validate_prepared "$prepared"

  frame_count=$(metadata_value FRAME_COUNT "$metadata")
  fps=$(metadata_value FPS "$metadata")
  duration=$(metadata_value INTRO_DURATION "$metadata")
  x=$(metadata_value ENTRY_X_MILLI "$metadata")
  y=$(metadata_value ENTRY_Y_MILLI "$metadata")
  audio=$(metadata_value AUDIO_ENABLED "$metadata")
  device=$(metadata_value AUDIO_DEVICE "$metadata")
  entry_x=$(awk -v value="$x" 'BEGIN { printf "%.3f", value / 1000 }')
  entry_y=$(awk -v value="$y" 'BEGIN { printf "%.3f", value / 1000 }')

  previous=$(plymouth-set-default-theme 2>/dev/null || echo omarchy)
  available_kb=$(df -Pk /boot | awk 'NR == 2 { print $4 }')
  required_kb=$(( $(du -sk "$prepared" | cut -f1) + 262144 ))
  [[ $available_kb =~ ^[0-9]+$ ]] && (( available_kb >= required_kb )) || {
    echo "Not enough free space on /boot to safely rebuild the UKI" >&2
    return 1
  }

  backup=$(mktemp -d /tmp/omaliveboot-backup.XXXXXXXX)
  if [[ -d $THEME_DIR ]]; then cp -a -- "$THEME_DIR" "$backup/theme"; had_theme=1; fi
  if [[ -f $HOOK_INSTALL ]]; then cp -a -- "$HOOK_INSTALL" "$backup/install-hook"; had_install_hook=1; fi
  if [[ -f $HOOK_RUNTIME ]]; then cp -a -- "$HOOK_RUNTIME" "$backup/runtime-hook"; had_runtime_hook=1; fi
  if [[ -f $HOOK_CONFIG ]]; then cp -a -- "$HOOK_CONFIG" "$backup/hook-config"; had_hook_config=1; fi
  [[ -f $STATE_DIR/previous-theme ]] && had_previous_state=1

  rollback_apply() {
    local status=$?
    (( status != 0 )) || status=1
    trap - ERR INT TERM
    set +e

    plymouth-set-default-theme "$previous" >/dev/null 2>&1
    rm -rf -- "$THEME_DIR"
    (( had_theme == 0 )) || cp -a -- "$backup/theme" "$THEME_DIR"

    rm -f -- "$HOOK_INSTALL" "$HOOK_RUNTIME" "$HOOK_CONFIG"
    (( had_install_hook == 0 )) || cp -a -- "$backup/install-hook" "$HOOK_INSTALL"
    (( had_runtime_hook == 0 )) || cp -a -- "$backup/runtime-hook" "$HOOK_RUNTIME"
    (( had_hook_config == 0 )) || cp -a -- "$backup/hook-config" "$HOOK_CONFIG"
    (( had_previous_state == 1 )) || rm -f -- "$STATE_DIR/previous-theme"

    rm -rf -- "${stage:-}" "$backup"
    echo "Luks Live installation failed; the previous on-disk configuration was restored." >&2
    exit "$status"
  }
  trap rollback_apply ERR INT TERM

  mkdir -p "$STATE_DIR" /etc/initcpio/install /etc/initcpio/hooks /etc/mkinitcpio.conf.d
  if [[ $previous != "$THEME_NAME" && ! -f $STATE_DIR/previous-theme ]]; then
    printf '%s\n' "$previous" >"$STATE_DIR/previous-theme"
  fi

  stage=$(mktemp -d /usr/share/plymouth/themes/.omaliveboot.XXXXXXXX)
  mkdir -p "$stage/frames"

  install -m 0644 "$SOURCE_ROOT/theme/omaliveboot.plymouth" "$stage/omaliveboot.plymouth"
  install -m 0644 "$SOURCE_ROOT/theme/omaliveboot.script.in" "$stage/omaliveboot.script"
  for ((index = 0; index < frame_count; index++)); do
    install -m 0644 "$prepared/frames/$index.png" "$stage/frames/$index.png"
  done

  for asset in lock.png entry.png bullet.png progress_box.png progress_bar.png; do
    install -m 0644 "/usr/share/plymouth/themes/omarchy/$asset" "$stage/$asset"
  done

  sed -i \
    -e "s/@FRAME_COUNT@/$frame_count/g" \
    -e "s/@INTRO_DURATION@/$duration/g" \
    -e "s/@FPS@/$fps/g" \
    -e "s/@ENTRY_X@/$entry_x/g" \
    -e "s/@ENTRY_Y@/$entry_y/g" \
    "$stage/omaliveboot.script"

  if grep -q "@FRAME_COUNT@\|@INTRO_DURATION@\|@FPS@\|@ENTRY_X@\|@ENTRY_Y@" "$stage/omaliveboot.script"; then
    echo "Theme script still contains unreplaced placeholders" >&2
    return 1
  fi

  cat >"$stage/boot.conf" <<EOF
INTRO_DURATION='$duration'
AUDIO_ENABLED='$audio'
AUDIO_DEVICE='$device'
EOF
  [[ $audio == 0 ]] || install -m 0644 "$prepared/intro.wav" "$stage/intro.wav"

  rm -rf -- "$THEME_DIR"
  mv -- "$stage" "$THEME_DIR"
  stage=

  install -m 0755 "$SOURCE_ROOT/initcpio/install/luks-live" "$HOOK_INSTALL"
  install -m 0755 "$SOURCE_ROOT/initcpio/hooks/luks-live" "$HOOK_RUNTIME"
  write_hook_config

  plymouth-set-default-theme "$THEME_NAME"
  rebuild_initramfs
  trap - ERR INT TERM
  rm -rf -- "$backup"
  echo "Luks Live installed. The next boot will play the intro before LUKS unlock."
}

revert_theme() {
  local previous=omarchy

  if [[ -s $STATE_DIR/previous-theme ]]; then
    read -r previous <"$STATE_DIR/previous-theme"
  fi
  [[ $previous =~ ^[A-Za-z0-9._-]+$ ]] || previous=omarchy

  rm -f -- "$HOOK_INSTALL" "$HOOK_RUNTIME" "$HOOK_CONFIG"
  plymouth-set-default-theme "$previous"
  rebuild_initramfs
  rm -rf -- "$THEME_DIR" "$STATE_DIR"
  echo "Luks Live removed. Plymouth restored to $previous."
}

case ${1:-} in
  --apply)
    (( $# == 2 )) || usage
    require_root
    apply_theme "$2"
    ;;
  --revert)
    (( $# == 1 )) || usage
    require_root
    revert_theme
    ;;
  --validate)
    (( $# == 2 )) || usage
    validate_prepared "$(realpath -e -- "$2")"
    echo "Prepared boot media is valid."
    ;;
  *) usage ;;
esac
