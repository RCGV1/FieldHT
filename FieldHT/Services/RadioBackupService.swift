import Foundation

@MainActor
public protocol RadioBackupTransport: AnyObject {
    var deviceInfo: DeviceInfo { get }
    func beginBackupOperation() async throws
    func endBackupOperation()
    func backupRegion() async throws -> Int
    func selectBackupRegion(_ index: Int) async throws
    func readBackupChannel(_ slot: Int) async throws -> Channel
    func writeBackupChannel(_ channel: Channel, region: Int?) async throws
    func readBackupRegionName(_ index: Int) async throws -> String
    func writeBackupRegionName(_ name: String, index: Int) async throws
    func readBackupSettings() async throws -> Data
    func writeBackupSettings(_ data: Data) async throws
    func readBackupBeacon() async throws -> Data?
    func writeBackupBeacon(_ data: Data) async throws
    func readBackupPath() async throws -> String?
    func writeBackupPath(_ path: String) async throws
    func readBackupButtons() async throws -> PFConfig?
    func writeBackupButtons(_ config: PFConfig) async throws
    func validateBackupChannels(_ channels: [Channel]) async throws
}

extension RadioBackupTransport {
    public func validateBackupChannels(_ channels: [Channel]) async throws {
        for channel in channels {
            let issues = ChannelFrequencyValidator.issues(for: channel, ranges: nil)
            if !issues.isEmpty { throw RadioBackupError.invalidFile(issues.joined(separator: " ")) }
        }
    }
}

@MainActor
public enum RadioBackupService {
    public typealias Progress = (Double, String) -> Void

    public static func capture(from radio: any RadioBackupTransport, progress: Progress) async throws -> RadioBackup {
        try await radio.beginBackupOperation()
        defer { radio.endBackupOperation() }
        let originalRegion = try await radio.backupRegion()
        do {
            let info = radio.deviceInfo
            let settings = try await radio.readBackupSettings()
            let beacon = try await radio.readBackupBeacon()
            let path = try await radio.readBackupPath()
            let buttons = try await radio.readBackupButtons()
            let count = min(30, info.channelCount)
            var regions: [RadioBackup.Region] = []
            for region in 0..<info.regionCount {
                try Task.checkCancellation()
                try await radio.selectBackupRegion(region)
                let name = try await radio.readBackupRegionName(region)
                var channels: [Channel] = []
                for slot in 0..<count {
                    try Task.checkCancellation()
                    channels.append(try await radio.readBackupChannel(slot))
                    progress(Double(region * count + slot + 1) / Double(max(1, info.regionCount * count)), "Reading group \(region + 1), channel \(slot + 1)")
                }
                regions.append(.init(index: region, name: name, channels: channels))
            }
            var vfos: [Channel] = []
            if info.supportsVFO {
                for slot in [251, 252] { vfos.append(try await radio.readBackupChannel(slot)) }
            }
            let backup = RadioBackup(device: info, regions: regions, vfoChannels: vfos, settingsPayload: settings,
                                     beaconPayload: beacon, aprsPath: path, programmableButtons: buttons)
            try backup.validate(for: info)
            try await returnToRegion(originalRegion, radio: radio)
            progress(1, "Backup complete")
            return backup
        } catch {
            try await returnToRegion(originalRegion, radio: radio)
            throw error
        }
    }

    public static func restore(_ backup: RadioBackup, to radio: any RadioBackupTransport, progress: Progress) async throws {
        // Reject malformed or incompatible files before acquiring the radio or writing anything.
        try backup.validate(for: radio.deviceInfo)
        try await radio.beginBackupOperation()
        defer { radio.endBackupOperation() }
        let originalRegion = try await radio.backupRegion()
        var startedWriting = false
        do {
            try await radio.validateBackupChannels(backup.regions.flatMap(\.channels) + backup.vfoChannels)
            let total = backup.regions.reduce(0) { $0 + $1.channels.count } + backup.vfoChannels.count
            var completed = 0
            for region in backup.regions.sorted(by: { $0.index < $1.index }) {
                try Task.checkCancellation()
                try await radio.selectBackupRegion(region.index)
                for channel in region.channels.sorted(by: { $0.channelID < $1.channelID }) {
                    try Task.checkCancellation()
                    startedWriting = true
                    try await radio.writeBackupChannel(channel, region: region.index)
                    let readback = try await radio.readBackupChannel(channel.channelID)
                    guard ProtocolEncoder.encodeChannel(readback) == ProtocolEncoder.encodeChannel(channel) else {
                        throw RadioBackupError.invalidFile("Channel \(channel.channelID + 1) did not verify after writing.")
                    }
                    completed += 1
                    progress(Double(completed) / Double(max(1, total)), "Restoring group \(region.index + 1), channel \(channel.channelID + 1)")
                }
                try await radio.writeBackupRegionName(region.name, index: region.index)
                guard try await radio.readBackupRegionName(region.index) == region.name else {
                    throw RadioBackupError.invalidFile("Group \(region.index + 1) name did not verify after writing.")
                }
            }
            for channel in backup.vfoChannels {
                try Task.checkCancellation()
                try await radio.writeBackupChannel(channel, region: nil)
                let readback = try await radio.readBackupChannel(channel.channelID)
                guard ProtocolEncoder.encodeChannel(readback) == ProtocolEncoder.encodeChannel(channel) else {
                    throw RadioBackupError.invalidFile("VFO memory did not verify after writing.")
                }
                completed += 1
            }
            if let beacon = backup.beaconPayload {
                try await radio.writeBackupBeacon(beacon)
                guard try await radio.readBackupBeacon() == beacon else { throw RadioBackupError.invalidFile("Beacon settings did not verify after writing.") }
            }
            if let path = backup.aprsPath {
                try await radio.writeBackupPath(path)
                guard try await radio.readBackupPath() == path else { throw RadioBackupError.invalidFile("Beacon path did not verify after writing.") }
            }
            if let buttons = backup.programmableButtons {
                try await radio.writeBackupButtons(buttons)
                guard try await radio.readBackupButtons() == buttons else { throw RadioBackupError.invalidFile("Programmable buttons did not verify after writing.") }
            }
            // Channel selections belong to the starting group, not the last
            // group visited while restoring the memory banks.
            try await returnToRegion(originalRegion, radio: radio)
            try await radio.writeBackupSettings(backup.settingsPayload)
            guard try await radio.readBackupSettings() == backup.settingsPayload else {
                throw RadioBackupError.invalidFile("Radio settings did not verify after writing.")
            }
            try await returnToRegion(originalRegion, radio: radio)
            progress(1, "Restore complete")
        } catch {
            try await returnToRegion(originalRegion, radio: radio)
            if startedWriting { throw RadioBackupError.partialRestore(error.localizedDescription) }
            throw error
        }
    }

    private static func returnToRegion(_ region: Int, radio: any RadioBackupTransport) async throws {
        // Cleanup must still run when the view's task was cancelled.
        try await Task { @MainActor in
            try await radio.selectBackupRegion(region)
            guard try await radio.backupRegion() == region else { throw RadioBackupError.regionRestoreFailed }
        }.value
    }
}
