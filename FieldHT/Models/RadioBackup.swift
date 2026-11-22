import Foundation

public struct RadioBackup: Codable {
    public struct Region: Codable {
        public let index: Int
        public let name: String
        public let channels: [Channel]
    }

    public let format: String
    public let version: Int
    public let createdAt: Date
    public let device: DeviceInfo
    public let regions: [Region]
    public let vfoChannels: [Channel]
    public let settingsPayload: Data
    public let beaconPayload: Data?
    public let aprsPath: String?
    public let programmableButtons: PFConfig?

    public init(device: DeviceInfo, regions: [Region], vfoChannels: [Channel], settingsPayload: Data,
                beaconPayload: Data?, aprsPath: String?, programmableButtons: PFConfig?) {
        format = "fieldht-radio-backup"
        version = 1
        createdAt = .now
        self.device = device
        self.regions = regions
        self.vfoChannels = vfoChannels
        self.settingsPayload = settingsPayload
        self.beaconPayload = beaconPayload
        self.aprsPath = aprsPath
        self.programmableButtons = programmableButtons
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> RadioBackup {
        guard data.count <= 4 * 1024 * 1024 else { throw RadioBackupError.invalidFile("The file is too large.") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(Self.self, from: data)
        try backup.validate(for: backup.device)
        return backup
    }

    public func validate(for target: DeviceInfo) throws {
        guard format == "fieldht-radio-backup", version == 1 else { throw RadioBackupError.invalidFile("Unsupported backup format or version.") }
        guard device.vendorID == target.vendorID, device.productID == target.productID,
              device.hardwareVersion == target.hardwareVersion, device.firmwareVersion == target.firmwareVersion,
              device.regionCount == target.regionCount, device.channelCount == target.channelCount else {
            throw RadioBackupError.incompatibleRadio
        }
        guard (1...64).contains(device.regionCount), (1...256).contains(device.channelCount),
              regions.count == device.regionCount, Set(regions.map(\.index)) == Set(0..<device.regionCount),
              (16...512).contains(settingsPayload.count) else { throw RadioBackupError.invalidFile("Incomplete radio settings or groups.") }
        _ = try ProtocolDecoder.decodeSettings(settingsPayload)
        if let beaconPayload {
            guard beaconPayload.count <= 512 else { throw RadioBackupError.invalidFile("Invalid beacon settings.") }
            _ = try ProtocolDecoder.decodeBeaconSettings(beaconPayload)
        }
        let slotIDs = Set(0..<min(30, device.channelCount))
        for region in regions {
            guard region.name.utf8.count <= 10, region.channels.count == slotIDs.count,
                  Set(region.channels.map(\.channelID)) == slotIDs else { throw RadioBackupError.invalidFile("Incomplete or duplicate memory slots.") }
        }
        let vfoIDs: Set<Int> = device.supportsVFO ? [251, 252] : []
        guard vfoChannels.count == vfoIDs.count, Set(vfoChannels.map(\.channelID)) == vfoIDs else {
            throw RadioBackupError.invalidFile("Incomplete VFO memories.")
        }
        for channel in regions.flatMap(\.channels) + vfoChannels {
            guard channel.name.utf8.count <= 10, channel.rxFreq.isFinite, channel.txFreq.isFinite,
                  channel.rxFreq >= 0, channel.txFreq >= 0,
                  channel.rxFreq < 1073.741824, channel.txFreq < 1073.741824 else {
                throw RadioBackupError.invalidFile("Invalid channel data.")
            }
            for tone in [channel.rxSubAudio, channel.txSubAudio].compactMap({ $0 }) {
                switch tone {
                case .dcs(let code):
                    guard (0...511).contains(code.n) else { throw RadioBackupError.invalidFile("Invalid DCS code.") }
                case .frequency(let hz):
                    guard hz.isFinite, (0...327.67).contains(hz) else { throw RadioBackupError.invalidFile("Invalid tone.") }
                }
            }
        }
        if let aprsPath, aprsPath.utf8.count > 255 { throw RadioBackupError.invalidFile("Invalid beacon path.") }
        if let programmableButtons {
            guard programmableButtons.pf.count <= 128,
                  Set(programmableButtons.pf.map { "\($0.buttonID):\($0.action.rawValue)" }).count == programmableButtons.pf.count,
                  programmableButtons.pf.allSatisfy({ (0...15).contains($0.buttonID) && (0...255).contains($0.effect.rawValue) }) else {
                throw RadioBackupError.invalidFile("Invalid programmable buttons.")
            }
        }
    }
}

public enum RadioBackupError: LocalizedError {
    case invalidFile(String)
    case incompatibleRadio
    case regionRestoreFailed
    case partialRestore(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFile(let detail): return "Invalid radio backup: \(detail)"
        case .incompatibleRadio: return "Restore requires the same radio model, hardware, firmware, and memory layout as the backup."
        case .regionRestoreFailed: return "The radio did not return to its original group. Reconnect and check the selected group."
        case .partialRestore(let detail): return "Restore stopped and some settings may already have changed. \(detail)"
        }
    }
}
