import Foundation

public enum RadioMaintenanceCodec {
    public static func settingAudioRelay(_ enabled: Bool, in payload: Data) throws -> Data {
        _ = try ProtocolDecoder.decodeSettings(payload)
        var bytes = Array(payload)
        guard bytes.count >= 3 else { throw RadioMaintenanceError.invalidPayload }
        bytes[2] = (bytes[2] & ~0x40) | (enabled ? 0x40 : 0)
        return Data(bytes)
    }

    public static func decodeFMStatus(_ data: Data) throws -> FMRadioStatus {
        let bytes = Array(data)
        guard bytes.count >= 4 else { throw RadioMaintenanceError.invalidPayload }
        return FMRadioStatus(
            isOn: bytes[0] & 0x80 != 0,
            isSeeking: bytes[0] & 0x10 != 0,
            frequencyMHz: Double(Int(bytes[2]) << 8 | Int(bytes[3])) / 100
        )
    }

    public static func encodeFMFrequency(_ frequencyMHz: Double) throws -> Data {
        guard frequencyMHz.isFinite, (64...108).contains(frequencyMHz) else {
            throw RadioMaintenanceError.unsupportedFrequency
        }
        let units = Int((frequencyMHz * 100).rounded())
        return Data([UInt8(units >> 8), UInt8(units & 0xFF)])
    }

    public static func decodeTrustedDevice(_ data: Data) throws -> TrustedBluetoothDevice {
        let bytes = Array(data)
        // Payload: index, reserved byte, six address bytes, UTF-8 name.
        guard bytes.count >= 8 else { throw RadioMaintenanceError.invalidPayload }
        let nameBytes = bytes.dropFirst(8).prefix { $0 != 0 }
        guard let name = String(bytes: nameBytes, encoding: .utf8) else {
            throw RadioMaintenanceError.invalidPayload
        }
        return TrustedBluetoothDevice(index: Int(bytes[0]), address: Data(bytes[2..<8]), name: name)
    }
}
