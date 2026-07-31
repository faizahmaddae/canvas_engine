#!/usr/bin/env bash
# Capture an emulator screenshot into build/ux_review/<section>/<name>.png
set -euo pipefail
ADB="$HOME/Library/Android/sdk/platform-tools/adb"
SEC="${1:?section}"; NAME="${2:?name}"
OUT="build/ux_review/$SEC/$NAME.png"
mkdir -p "$(dirname "$OUT")"
"$ADB" -s emulator-5554 exec-out screencap -p > "$OUT"
echo "$OUT"
