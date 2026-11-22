#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_binary="$(mktemp -t fieldht-radio-tools)"
trap 'rm "$test_binary"' EXIT
xcrun swiftc -parse-as-library \
  FieldHT/Protocol/Bitfield.swift FieldHT/Models/*.swift \
  FieldHT/Protocol/ProtocolEncoder.swift FieldHT/Protocol/ProtocolDecoder.swift \
  FieldHT/Protocol/ProtocolConstants.swift FieldHT/Protocol/ProtocolError.swift FieldHT/Protocol/RadioMaintenanceCodec.swift \
  FieldHT/Command/RadioMessage.swift FieldHT/Command/EventMessage.swift \
  FieldHT/Services/FirmwareUpdateService.swift FieldHT/Services/RadioBackupService.swift \
  Tests/RadioToolsTests.swift -o "$test_binary"
"$test_binary" "$@"
