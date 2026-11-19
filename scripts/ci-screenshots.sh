#!/usr/bin/env bash
# Boots the simulator used by the test step and saves UI screenshots.
set -euo pipefail

UDID="${1:?simulator UDID}"
BUNDLE_ID="com.grandelevas.wakemeup"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ROOT}/screenshots"
mkdir -p "${OUT}"

APP="$(find "${ROOT}/DerivedData/Build/Products" -type d -name "WakeMeUp.app" -path "*iphonesimulator*" -print -quit)"
if [[ -z "${APP}" ]]; then
  echo "WakeMeUp.app was not found under DerivedData" >&2
  exit 1
fi
echo "App: ${APP}"
find "${APP}" -name "*.wav" -print

xcrun simctl boot "${UDID}" || true
xcrun simctl bootstatus "${UDID}" -b
xcrun simctl install "${UDID}" "${APP}"
xcrun simctl ui "${UDID}" appearance dark || true
xcrun simctl status_bar "${UDID}" override \
  --time "9:41" \
  --batteryState charged \
  --batteryLevel 100 \
  --wifiBars 3 \
  --cellularMode active \
  --cellularBars 4 || true

capture() {
  local name="$1"
  shift
  xcrun simctl terminate "${UDID}" "${BUNDLE_ID}" || true
  xcrun simctl launch "${UDID}" "${BUNDLE_ID}" "$@"
  sleep 4
  xcrun simctl io "${UDID}" screenshot "${OUT}/${name}.png"
}

capture paywall-en
capture alarms-en -WakeMeUpDemo -WakeMeUpScreen alarms
capture editor-en -WakeMeUpDemo -WakeMeUpScreen editor
capture groups-en -WakeMeUpDemo -WakeMeUpScreen groups
capture sharing-en -WakeMeUpDemo -WakeMeUpScreen sharing
capture ringing-en -WakeMeUpDemo -WakeMeUpScreen ringing
capture alarms-pl -AppleLanguages "(pl)" -AppleLocale "pl_PL" -WakeMeUpDemo -WakeMeUpScreen alarms

echo "Wrote screenshots to ${OUT}"
ls -la "${OUT}"
