#!/usr/bin/env bash
set -euo pipefail

export PATH="/home/jose/development/flutter/bin:$PATH"

cd /mnt/c/Users/jose/src/work/hydracamv2
/home/jose/development/flutter/bin/flutter config --enable-linux-desktop
/home/jose/development/flutter/bin/flutter pub get
/home/jose/development/flutter/bin/flutter build linux --debug
