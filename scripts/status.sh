#!/usr/bin/env bash

set -euo pipefail

theme=$(plymouth-set-default-theme 2>/dev/null || true)
installed=0
if [[ $theme == omaliveboot ]] || [[ -d /usr/share/plymouth/themes/omaliveboot ]] || [[ -d /var/lib/omaliveboot ]] || [[ -f /etc/initcpio/hooks/luks-live ]] || [[ -f /etc/mkinitcpio.conf.d/zz-omaliveboot.conf ]]; then
  installed=1
fi

audio_device="$($(dirname "$0")/audio-device.sh 2>/dev/null || true)"

printf 'installed=%s\n' "$installed"
printf 'theme=%s\n' "${theme:-unknown}"
printf 'audio_device=%s\n' "${audio_device:-unavailable}"
printf 'ffmpeg=%s\n' "$(command -v ffmpeg >/dev/null 2>&1 && echo available || echo missing)"
