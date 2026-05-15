#!/usr/bin/env zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$PROJECT_ROOT/FieldHT.xcodeproj}"
SCHEME="${SCHEME:-FieldHT}"
CONFIGURATION="${CONFIGURATION:-Debug}"
BUNDLE_ID="${BUNDLE_ID:-BenFaer.FieldHT}"
DEVICE_ID="${DEVICE_ID:-${XCODE_DESTINATION_ID:-}}"
XCODE_DESTINATION_ID="${XCODE_DESTINATION_ID:-$DEVICE_ID}"
SOAK_SECONDS="${SOAK_SECONDS:-630}"
PROVE_MINUTES="${PROVE_MINUTES:-10}"
ALLOW_LOCKED="${ALLOW_LOCKED:-0}"
OUTPUT_DIR="${OUTPUT_DIR:-/private/tmp/fieldht_soak_$(date +%Y%m%d_%H%M%S)}"

if [[ -z "$DEVICE_ID" || -z "$XCODE_DESTINATION_ID" ]]; then
  echo "Set DEVICE_ID to the plugged-in iPhone UDID or CoreDevice identifier."
  echo "Connected devices:"
  xcrun devicectl list devices
  exit 2
fi

mkdir -p "$OUTPUT_DIR"

echo "Project: $PROJECT_PATH"
echo "Scheme: $SCHEME"
echo "Device: $DEVICE_ID"
echo "Output: $OUTPUT_DIR"

LOCK_OUTPUT="$OUTPUT_DIR/lock-state.txt"
xcrun devicectl device info lockState --device "$DEVICE_ID" | tee "$LOCK_OUTPUT"
if grep -q "passcodeRequired: true" "$LOCK_OUTPUT" && [[ "$ALLOW_LOCKED" != "1" ]]; then
  echo
  echo "Device is locked. Unlock the iPhone and set Auto-Lock to Never for a foreground soak test."
  echo "Re-run with ALLOW_LOCKED=1 only if you intentionally want to test locked-device behavior."
  exit 4
fi

echo
echo "Building app..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "id=$XCODE_DESTINATION_ID" \
  build | tee "$OUTPUT_DIR/xcodebuild.log"

BUILD_SETTINGS="$OUTPUT_DIR/build-settings.txt"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "id=$XCODE_DESTINATION_ID" \
  -showBuildSettings > "$BUILD_SETTINGS"

BUILT_PRODUCTS_DIR="$(awk -F '= ' '/^[[:space:]]*BUILT_PRODUCTS_DIR = / { print $2; exit }' "$BUILD_SETTINGS")"
FULL_PRODUCT_NAME="$(awk -F '= ' '/^[[:space:]]*FULL_PRODUCT_NAME = / { print $2; exit }' "$BUILD_SETTINGS")"
APP_PATH="$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at $APP_PATH"
  exit 5
fi

echo
echo "Installing $APP_PATH..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" | tee "$OUTPUT_DIR/install.log"

echo
echo "Launching $BUNDLE_ID..."
xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  --terminate-existing \
  "$BUNDLE_ID" | tee "$OUTPUT_DIR/launch.log"

echo
echo "Waiting ${SOAK_SECONDS}s for connection soak..."
remaining="$SOAK_SECONDS"
while (( remaining > 0 )); do
  sleep_for="$remaining"
  if (( sleep_for > 30 )); then
    sleep_for=30
  fi
  sleep "$sleep_for"
  remaining=$(( remaining - sleep_for ))
  echo "  $(date '+%H:%M:%S') remaining=${remaining}s"
done

echo
echo "Pulling BLE capture files..."
captures=()
if xcrun devicectl device copy from \
  --device "$DEVICE_ID" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --source Library/Caches/fieldht_ble_capture.jsonl.1 \
  --destination "$OUTPUT_DIR/fieldht_ble_capture.jsonl.1"; then
  captures+=("$OUTPUT_DIR/fieldht_ble_capture.jsonl.1")
else
  echo "No rotated capture file found."
fi

if xcrun devicectl device copy from \
  --device "$DEVICE_ID" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --source Library/Caches/fieldht_ble_capture.jsonl \
  --destination "$OUTPUT_DIR/fieldht_ble_capture.jsonl"; then
  captures+=("$OUTPUT_DIR/fieldht_ble_capture.jsonl")
else
  echo "No current capture file found."
fi

if (( ${#captures[@]} == 0 )); then
  echo "No capture files were pulled."
  exit 6
fi

echo
echo "Analyzing capture..."
python3 "$PROJECT_ROOT/scripts/analyze_ble_capture.py" "${captures[@]}" --prove-minutes "$PROVE_MINUTES" | tee "$OUTPUT_DIR/analyze.log"

echo
echo "Soak proof artifacts saved in $OUTPUT_DIR"
