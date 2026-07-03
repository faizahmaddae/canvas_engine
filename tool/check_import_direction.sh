#!/usr/bin/env bash
# Engine import-direction gate.
#
# AGENTS.md: "Inverted imports are bugs. A file in engine/ must not
# import anything from application/ or presentation/." This script is
# the CI teeth for that rule: it fails when any Dart file under
# lib/features/editor/engine/ imports an application/ or
# presentation/ directory (relative or package: form) or the app
# shell (package:canvas_engine/app/).
#
# Scope note: the same rule conceptually applies one level up
# (application/ must not import presentation/), but two known
# violations exist today (recent_colors_controller.dart consumers —
# roadmap Phase 0.6). Extend this script to cover application/ once
# that lands, so CI is green from day one.
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

if [[ "$status" -eq 0 ]]; then
  echo 'OK: engine import direction clean.'
fi
exit "$status"
