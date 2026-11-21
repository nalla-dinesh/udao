#!/usr/bin/env bash
# UDAO structure validator — runs anywhere, no Flutter required.
# The agent uses it for static self-verification; CI and humans use it
# as a cheap invariant check (permissions, fonts, icon bans).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

need() {
  if [ -f "$ROOT/$1" ]; then
    echo "  ok    $1"
  else
    echo "  MISSING  $1 — $2"
    fail=1
  fi
}

echo "== Root =="
need "pubspec.yaml" "project manifest"
need "analysis_options.yaml" "strict lints"
need "LICENSE" "AGPL-3.0"
need "README.md" "docs"
need "CHANGELOG.md" "changelog"
need "AGENT_LOG.md" "phase tracking"

echo "== Fonts (10 expected) =="
font_count=$(ls -1 "$ROOT/assets/fonts/"*.ttf 2>/dev/null | wc -l)
if [ "$font_count" -eq 10 ]; then
  echo "  ok    $font_count TTFs"
else
  echo "  FAIL  expected 10 TTFs, found $font_count"
  fail=1
fi

echo "== Brand icons (8 expected) =="
icon_count=$(ls -1 "$ROOT/assets/icons/"*.svg 2>/dev/null | wc -l)
if [ "$icon_count" -eq 8 ]; then
  echo "  ok    $icon_count SVGs"
else
  echo "  FAIL  expected 8 SVGs, found $icon_count"
  fail=1
fi

echo "== Permission audit (ADR-0001 / ADR-0002) =="
# INTERNET must appear ONLY in debug/profile overlays — never in
# main/play/power (release paths).
for src in main play power; do
  if grep -q "android.permission.INTERNET" \
      "$ROOT/android/app/src/$src/AndroidManifest.xml" 2>/dev/null; then
    echo "  FAIL  INTERNET found in src/$src manifest"
    fail=1
  else
    echo "  ok    no INTERNET in src/$src"
  fi
done
for src in debug profile; do
  if grep -q "android.permission.INTERNET" \
      "$ROOT/android/app/src/$src/AndroidManifest.xml" 2>/dev/null; then
    echo "  ok    INTERNET present in src/$src (dev-only, expected)"
  else
    echo "  FAIL  src/$src must declare INTERNET for the VM service"
    fail=1
  fi
done
if grep -q "RECEIVE_SMS" "$ROOT/android/app/src/power/AndroidManifest.xml"; then
  echo "  ok    power flavor declares RECEIVE_SMS"
else
  echo "  FAIL  power flavor must declare RECEIVE_SMS"
  fail=1
fi
if grep -q "RECEIVE_SMS\|READ_SMS" \
    "$ROOT/android/app/src/main/AndroidManifest.xml"; then
  echo "  FAIL  main manifest must not declare SMS permissions"
  fail=1
else
  echo "  ok    no SMS permissions in main"
fi

echo "== Code hygiene =="
if grep -rn "print(" "$ROOT/lib/" >/dev/null 2>&1; then
  echo "  FAIL  print( found in lib/ — use UdaoLogger"
  fail=1
else
  echo "  ok    no print( in lib/"
fi
if grep -rEn "\b(Icons|CupertinoIcons)\." "$ROOT/lib/" >/dev/null 2>&1; then
  echo "  FAIL  banned icon classes in lib/ (use AppIcons / phosphor_flutter)"
  fail=1
else
  echo "  ok    no banned icon classes in lib/"
fi

echo ""
if [ "$fail" -eq 0 ]; then
  echo "ALL STRUCTURE CHECKS PASSED"
else
  echo "STRUCTURE CHECKS FAILED"
  exit 1
fi
