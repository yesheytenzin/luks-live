#!/usr/bin/env bash

set -euo pipefail

command -v aplay >/dev/null 2>&1 || exit 1

aplay -l 2>/dev/null | awk '
  /^card [0-9]+:/ && /device [0-9]+:/ && /Analog/ {
    card = $3
    sub(/:$/, "", card)
    for (i = 1; i <= NF; i++) {
      if ($i == "device") {
        device = $(i + 1)
        sub(/:$/, "", device)
        print "hw:" card "," device
        exit
      }
    }
  }
'
