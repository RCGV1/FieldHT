import Foundation

public struct FMRadioStatus: Equatable, Sendable {
    public let isOn: Bool
    public let isSeeking: Bool
    public let frequencyMHz: Double
}

public struct TrustedBluetoothDevice: Identifiable, Equatable, Sendable {
    public let index: Int
    public let address: Data
    public let name: String

    public var id: String { formattedAddress }
    public var formattedAddress: String {
        address.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

public enum RadioMaintenanceError: LocalizedError {
    case invalidPayload
    case unsupportedFrequency
    case operationInProgress
    case radioBusy

    public var errorDescription: String? {
        switch self {
        case .invalidPayload: return "The radio returned an invalid response."
        case .unsupportedFrequency: return "Enter an FM broadcast frequency between 64 and 108 MHz."
        case .operationInProgress: return "Wait for the radio backup or restore to finish."
        case .radioBusy: return "Stop scanning and transmitting before backing up or restoring the radio."
        }
    }
}

public enum ChannelFrequencyValidator {
    public static func issues(for channel: Channel, ranges: DeviceFrequencyRanges?) -> [String] {
        // Zeroed slots are empty memories, not frequencies to tune.
        if channel.rxFreq == 0 && channel.txFreq == 0 { return [] }
        var issues: [String] = []
        validate(channel.rxFreq, modulation: channel.rxMod, direction: .receive, ranges: ranges, into: &issues)
        if !channel.txDisable {
            validate(channel.txFreq, modulation: channel.txMod, direction: .transmit, ranges: ranges, into: &issues)
        } else if !channel.txFreq.isFinite || channel.txFreq < 0 || channel.txFreq >= 1073.741824 {
            issues.append("TX frequency is invalid.")
        }
        return issues
    }

    private static func validate(
        _ frequency: Double, modulation: ModulationType, direction: FrequencyRangeDirection,
        ranges: DeviceFrequencyRanges?, into issues: inout [String]
    ) {
        let label = direction == .receive ? "RX" : "TX"
        guard frequency.isFinite, frequency > 0, frequency * 1_000_000 < 1_073_741_824 else {
            issues.append("\(label) frequency is invalid.")
            return
        }
        guard let ranges, !ranges.ranges.isEmpty else { return }
        let modulation: FrequencyRangeModulation = switch modulation {
        case .fm: .fm
        case .am: .am
        case .dmr: .dmr
        }
        if !ranges.ranges.contains(where: { $0.direction == direction && $0.modulation == modulation && $0.contains(frequency) }) {
            issues.append(String(format: "%@ %.5f MHz is outside this radio's supported %@ bands.", label, frequency, String(describing: modulation).uppercased()))
        }
    }
}
