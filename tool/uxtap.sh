#!/usr/bin/env bash
# Tap/swipe/type on the emulator using *displayed screenshot* coords (896x2000 space).
# Usage: uxtap.sh tap X Y | swipe X1 Y1 X2 Y2 [ms] | text "..." | key KEYCODE | back
set -euo pipefail
ADB="$HOME/Library/Android/sdk/platform-tools/adb"; DEV="emulator-5554"
K=1.428571   # 1280/896
m() { python3 -c "print(int(round($1*$K)))"; }
case "${1}" in
  tap)   "$ADB" -s $DEV shell input tap "$(m "$2")" "$(m "$3")" ;;
  swipe) "$ADB" -s $DEV shell input swipe "$(m "$2")" "$(m "$3")" "$(m "$4")" "$(m "$5")" "${6:-300}" ;;
  text)  "$ADB" -s $DEV shell input text "$2" ;;
  key)   "$ADB" -s $DEV shell input keyevent "$2" ;;
  back)  "$ADB" -s $DEV shell input keyevent 4 ;;
  *) echo "unknown: $1" >&2; exit 1 ;;
esac
