#!/usr/bin/env bash
# phase-05 — OEM survival verification protocol (adb).
#
# Usage:  bash tools/oem_test.sh [serial]
#   (optional serial for multi-device setups, passed to adb -s)
#
# Read-only checks against a REAL phone with the app installed:
#   1. notification-listener binding
#   2. battery-optimization exemption + doze whitelist
#   3. app standby bucket + background restriction
#   4. last process exit reasons (API 30+)
#   5. WorkManager/job state for our package
#   6. keep-alive foreground service state (when armed)
#
# Pair with the manual drill in docs/oem-survival.md §8 (reboot,
# swipe-away, cleaner toggling). This script NEVER modifies device
# state — observation only, honesty only.
set -euo pipefail

PKG="in.udao.app"
SERIAL="${1:-}"
ADB="adb"
if [[ -n "$SERIAL" ]]; then
  ADB="adb -s $SERIAL"
fi

hr() { printf '\n──────── %s ────────\n' "$1"; }
sdk="$("$ADB" shell getprop ro.build.version.sdk | tr -d '[:space:]')"
mfr="$("$ADB" shell getprop ro.product.manufacturer | tr -d '[:space:]')"
brand="$("$ADB" shell getprop ro.product.brand | tr -d '[:space:]')"

echo "UDAO OEM survival check"
echo "device: $mfr / $brand (SDK $sdk)"

hr "1. notification-listener binding"
"$ADB" shell dumpsys notification 2>/dev/null | grep -i -A2 "udao" || \
  echo "  (no udao lines in dumpsys notification — listener not bound?)"

hr "2. battery optimization + doze whitelist"
"$ADB" shell dumpsys deviceidle 2>/dev/null | grep -i "udao" || \
  echo "  (udao absent from deviceidle whitelist — NOT exempt)"
echo "  quick check (null = not exempt):"
"$ADB" shell dumpsys deviceidle whitelist 2>/dev/null | grep -i udao || true

hr "3. standby bucket + background restriction"
"$ADB" shell am get-standby-bucket "$PKG" 2>/dev/null || \
  echo "  (am get-standby-bucket unavailable)"
echo "  buckets: 5=exempted 10=active 20=working 30=frequent 40=rare 45=restricted"
"$ADB" shell dumpsys activity 2>/dev/null | grep -i "background-restricted" | head -2 || true

hr "4. last exit reasons (API 30+)"
if [[ "$sdk" -ge 30 ]]; then
  "$ADB" shell dumpsys activity exit-info "$PKG" 2>/dev/null | head -30 || \
    echo "  (no exit info recorded)"
else
  echo "  SDK $sdk < 30 — ApplicationExitInfo unavailable (dashboard shows the honest empty state)"
fi

hr "5. WorkManager / jobs state"
"$ADB" shell dumpsys jobscheduler 2>/dev/null | grep -i -B1 -A6 "udao" | head -60 || \
  echo "  (no udao jobs found — open the app once to arm the watchdog)"

hr "6. keep-alive foreground service (when armed)"
"$ADB" shell dumpsys activity services "$PKG" 2>/dev/null | grep -i -A4 "KeepAlive" || \
  echo "  (keep-alive not running — expected unless you armed it on the health screen)"

hr "manual drill reminder (docs/oem-survival.md §8)"
cat <<'EOF'
  1. reboot -> health screen within 2 min -> stamp back to SHARP
  2. swipe app away -> ₹1 UPI test txn -> still lands (WAL)
  3. toggle battery saver / OEM cleaner -> escalation arrives <= 1/24h
  4. follow in-app OEM guide -> re-check device-truth card
EOF

echo
echo "done. observation only — nothing was modified on the device."
