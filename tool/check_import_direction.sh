#!/usr/bin/env bash
# Import-direction gate.
#
# AGENTS.md: "Inverted imports are bugs." engine -> application ->
# presentation is one-way. This script is the CI teeth for two rules:
#
#   1. No Dart file under lib/features/editor/engine/ imports an
#      application/ or presentation/ directory (relative or package:
#      form) or the app shell (package:canvas_engine/app/).
#   2. No Dart file under any lib/**/application/ directory imports
#      a presentation/ directory.
set -euo pipefail
cd "$(dirname "$0")/.."

engine_dir='lib/features/editor/engine'
status=0

layer_violations=$(grep -rn --include='*.dart' -E \
  "^import +'([^']*/)?(application|presentation)/" \
  "$engine_dir" || true)
if [[ -n "$layer_violations" ]]; then
  echo 'FAIL: engine/ imports application/ or presentation/:'
  echo "$layer_violations"
  status=1
fi

app_violations=$(grep -rn --include='*.dart' -E \
  "^import +'package:canvas_engine/app/" \
  "$engine_dir" || true)
if [[ -n "$app_violations" ]]; then
  echo 'FAIL: engine/ imports the app shell (package:canvas_engine/app/):'
  echo "$app_violations"
  status=1
fi

application_violations=$(find lib -type d -name application \
  -exec grep -rn --include='*.dart' -E \
  "^import +'([^']*/)?presentation/" {} + || true)
if [[ -n "$application_violations" ]]; then
  echo 'FAIL: application/ imports presentation/:'
  echo "$application_violations"
  status=1
fi

if [[ "$status" -eq 0 ]]; then
  echo 'OK: import direction clean (engine + application).'
fi
exit "$status"
