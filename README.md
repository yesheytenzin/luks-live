# Luks Live

Luks Live is an Omarchy Quattro bar plugin for designing and installing a
one-shot audiovisual intro before the LUKS disk password prompt.

The manager shows the selected video in a live preview, plays its sound when
enabled, stops at the configured intro length, and overlays the real Omarchy
Plymouth password assets at the selected position. Applying the preview turns
the clip into optimized Plymouth frames and rebuilds the Omarchy UKI.

## Boot Sequence

```text
Limine -> kernel/KMS -> Plymouth video + optional sound -> final frame
       -> LUKS password prompt -> root mount -> SDDM autologin -> Hyprland
```

The password request does not start until the intro finishes. Luks Live does
not replace cryptsetup or process the disk password; Omarchy's existing
mkinitcpio encryption hook remains responsible for unlocking the disk.

## Features

- Live video and sound preview in the Quattro panel
- Plugin-owned `assets/` library for manually managed live wallpapers
- One-shot playback that freezes on the last generated frame
- Real Omarchy lock, entry, bullet, and progress assets in preview and Plymouth
- Configurable 1-5 second length and 8-20 FPS
- Nine password-field positions
- Optional built-in-speaker PCM soundtrack with a volume setting
- Silent fallback when early-boot audio is unavailable
- Transactional media preparation with a 128 MiB payload limit
- One-click apply and revert through polkit

## Install

```bash
omarchy plugin add https://github.com/yesheytenzin/luks-live.git --enable
```

The `LUKS` widget appears in the right bar section. Open it, select **Open
assets**, manually add a short video to that folder, and select **Refresh**.
Choose the discovered clip, replay the final-frame transition until it looks
right, and select **Apply to next boot**. Polkit requests administrator
authorization before system files or the UKI are changed.

The UI does not upload, import, move, or copy videos. It only lists supported
files already present in the plugin's `assets/` folder. Personal videos are
ignored by Git; only `assets/README.md` is tracked.

The plugin expects the standard Omarchy packages, including `plymouth`,
`mkinitcpio`, `ffmpeg`, and `alsa-utils`. Sound currently targets the first
built-in analog ALSA device. Bluetooth, USB, and HDMI boot audio are not used.

## Update

```bash
omarchy plugin update tenzin.luks-live
```

## Remove

Use **Revert** in the Luks Live panel before removing the plugin. Revert
restores the previous Plymouth theme and removes the initramfs hook; removing
the shell plugin alone cannot undo those privileged boot changes.

```bash
omarchy plugin remove tenzin.luks-live
```

## System Changes

Applying installs only these system-owned components:

```text
/usr/share/plymouth/themes/omaliveboot/
/etc/initcpio/install/luks-live
/etc/initcpio/hooks/luks-live
/etc/mkinitcpio.conf.d/zz-omaliveboot.conf
/var/lib/omaliveboot/previous-theme
```

The mkinitcpio drop-in dynamically inserts `luks-live` immediately before
`encrypt` or `sd-encrypt`, so it follows future Omarchy hook-order changes.
Revert removes these files, restores the previous Plymouth theme, and rebuilds
the UKI.

No file under `/usr/share/omarchy` is modified.

## Security And Recovery

The video frames and WAV file must be available before disk unlock, so they are
stored unencrypted in the initramfs/UKI on the EFI System Partition. Do not use
private media.

If Plymouth or the theme cannot load, boot once with these kernel parameters to
reach Omarchy's text LUKS prompt without the custom gate:

```text
plymouth.enable=0 disablehooks=plymouth,luks-live
```

After logging in, use the plugin's **Revert** action.

Audio playback is best effort. The hook has a fixed upper bound equal to the
intro length, stops any lingering `aplay` process, and always proceeds to LUKS.

## Development

```bash
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml Preview.qml
bash -n scripts/*.sh initcpio/install/luks-live initcpio/hooks/luks-live
```

To test frame and WAV preparation without changing the boot configuration:

```bash
scripts/prepare.sh ./clip.mp4 2500 12 1280 720 500 680 1 70
scripts/install.sh --validate "$HOME/.cache/omaliveboot/prepared"
```

Actual boot installation should be performed from the plugin UI so preparation
runs unprivileged and only the validated publication step runs through polkit.
