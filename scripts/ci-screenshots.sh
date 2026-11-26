#!/usr/bin/env bash
# Saves App Store screenshots at 1320x2868 from an iPhone Pro Max simulator.
set -euo pipefail

BUNDLE_ID="com.grandelevas.wakemeup"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ROOT}/screenshots/appstore"
mkdir -p "${OUT}"

APP="$(find "${ROOT}/DerivedData/Build/Products" -type d -name "WakeMeUp.app" -path "*iphonesimulator*" -print -quit)"
if [[ -z "${APP}" ]]; then
  echo "WakeMeUp.app was not found under DerivedData" >&2
  exit 1
fi
echo "App: ${APP}"

UDID="$(python3 "${ROOT}/scripts/select-screenshot-simulator.py")"
echo "Screenshot simulator ${UDID}"

xcrun simctl boot "${UDID}" || true
xcrun simctl bootstatus "${UDID}" -b
xcrun simctl install "${UDID}" "${APP}"
xcrun simctl ui "${UDID}" appearance light
xcrun simctl status_bar "${UDID}" override \
  --time "9:41" \
  --batteryState charged \
  --batteryLevel 100 \
  --wifiBars 3 \
  --cellularMode active \
  --cellularBars 4

expect_pixels() {
  local file="$1"
  local width height
  width="$(sips -g pixelWidth "${file}" | awk '/pixelWidth/ { print $2 }')"
  height="$(sips -g pixelHeight "${file}" | awk '/pixelHeight/ { print $2 }')"
  echo "${file}: ${width}x${height}"
  if [[ "${width}" != "1320" || "${height}" != "2868" ]]; then
    echo "Expected 1320x2868, got ${width}x${height}" >&2
    exit 1
  fi
}

capture() {
  local name="$1"
  shift
  xcrun simctl terminate "${UDID}" "${BUNDLE_ID}" || true
  xcrun simctl launch "${UDID}" "${BUNDLE_ID}" "$@"
  sleep 5
  xcrun simctl io "${UDID}" screenshot "${OUT}/${name}.png"
  expect_pixels "${OUT}/${name}.png"
}

screens=(
  "01-editor editor"
  "02-ringing ringing"
  "03-sharing sharing"
  "04-nap nap"
  "05-calendar calendar"
  "06-achievements achievements"
  "07-alarms alarms"
)

for language in pl en; do
  if [[ "${language}" == "pl" ]]; then
    lang_args=(-AppleLanguages "(pl)" -AppleLocale "pl_PL")
  else
    lang_args=(-AppleLanguages "(en)" -AppleLocale "en_US")
  fi
  for entry in "${screens[@]}"; do
    file="${entry%% *}"
    screen="${entry##* }"
    capture "${language}-${file}" "${lang_args[@]}" -WakeMeUpDemo -WakeMeUpScreen "${screen}"
  done
done

echo "Wrote App Store screenshots to ${OUT}"
ls -la "${OUT}"
