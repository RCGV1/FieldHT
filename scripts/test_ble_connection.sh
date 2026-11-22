#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d -t fieldht-ble-tests)"
trap 'for file in "$test_dir"/*; do if [[ -f "$file" ]]; then rm "$file"; fi; done; rmdir "$test_dir"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -parse-as-library \
  -emit-library -emit-module -module-name CoreBluetooth \
  Tests/Support/CoreBluetooth.swift -o "$test_dir/libCoreBluetooth.dylib"
xcrun swiftc -swift-version 6 -default-isolation MainActor -parse-as-library \
  -I "$test_dir" -L "$test_dir" -lCoreBluetooth \
  FieldHT/BLE/BLEConnection.swift Tests/BLEConnectionLifecycleTests.swift \
  -o "$test_dir/ble-tests"
DYLD_LIBRARY_PATH="$test_dir${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" "$test_dir/ble-tests"
