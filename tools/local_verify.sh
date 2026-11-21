#!/usr/bin/env bash
# UDAO local verification — THE gate before moving to the next phase.
# Runs on the human's machine (requires Flutter on PATH).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "== flutter pub get =="
flutter pub get

echo "== flutter analyze (expect: No issues found!) =="
flutter analyze

echo "== dart format check =="
dart format --set-exit-if-changed lib test

echo "== flutter test =="
flutter test

echo ""
echo "== Structure checks =="
bash tools/bootstrap.sh

echo ""
echo "Remaining manual steps (see PHASE_00_COMPLETION_REPORT.md):"
echo "  flutter run --flavor play    # dark screen, flame logo, Syne text"
echo "  flutter run --flavor power   # same, versionName suffix -power"
