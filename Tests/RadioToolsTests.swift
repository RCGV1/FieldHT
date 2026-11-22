import Foundation

@main
@MainActor
enum RadioToolsTests {
    static func main() async throws {
        try testMaintenanceCodec()
        try testAudioRelay()
        try testSatelliteRetuning()
        try testFrequencyRangeDecoding()
        try testFrequencyValidation()
        try testFirmwareProtocol()
        try await testBackupCaptureAndRestore()
        try await testBackupFailures()
        print("RadioToolsTests passed: FM/pairing codecs, Audio Relay bit preservation, Doppler retuning policy, band parsing/validation, firmware framing, and backup/restore integrity")
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--check-firmware",
           let productID = Int(CommandLine.arguments[2]) {
            let update = try await FirmwareUpdateService().check(productID: productID)
            print("Live firmware check passed: \(update?.versionDescription ?? "no published firmware")")
        }
    }

    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw TestFailure(message: message) }
    }

    static func expectThrow(_ message: String, _ action: () throws -> Void) throws {
        do { try action() } catch { return }
        throw TestFailure(message: message)
    }

    static func testMaintenanceCodec() throws {
        let status = try RadioMaintenanceCodec.decodeFMStatus(Data([0xD0, 0, 0x29, 0x0E]))
        try expect(status.isOn && status.isSeeking && status.frequencyMHz == 105.10, "FM flags and 10 kHz frequency units must match the capture")
        try expect(try RadioMaintenanceCodec.encodeFMFrequency(91.5) == Data([0x23, 0xBE]), "FM tuning must use big-endian 10 kHz units")
        for size in 0..<4 {
            try expectThrow("Truncated FM status must fail") { _ = try RadioMaintenanceCodec.decodeFMStatus(Data(repeating: 0, count: size)) }
        }
        for frequency in [Double.nan, .infinity, -1, 0, 63.99, 108.01] {
            try expectThrow("Invalid FM frequency must fail") { _ = try RadioMaintenanceCodec.encodeFMFrequency(frequency) }
        }
        let packet = Data([2, 0, 0x60, 0xB7, 0x6E, 0x0E, 0xD2, 0x61]) + Data("Speaker Mic\0".utf8)
        let device = try RadioMaintenanceCodec.decodeTrustedDevice(packet)
        try expect(device.index == 2 && device.name == "Speaker Mic" && device.formattedAddress == "60:B7:6E:0E:D2:61", "Pairing name and address offsets must match the decoded protocol")
        for size in 0..<8 {
            try expectThrow("Truncated pairing entry must fail") { _ = try RadioMaintenanceCodec.decodeTrustedDevice(Data(packet.prefix(size))) }
        }
    }

    static func testAudioRelay() throws {
        let payload = Data([0x5D, 0x43, 0xA7, 0x47, 0x1A, 0x1E, 0x1C, 0x80, 0xA1, 0x01, 0x0C,
                            0x20, 0, 0, 0, 0x78, 0, 0, 0, 0, 0, 0, 0xDE, 0xAD, 0xBE, 0xEF])
        let enabled = try RadioMaintenanceCodec.settingAudioRelay(true, in: payload)
        try expect(try ProtocolDecoder.decodeSettings(enabled).autoRelayEn, "Audio Relay must use settings payload byte 2 bit 0x40")
        try expect(zip(enabled, payload).enumerated().allSatisfy { index, pair in
            pair.0 == (index == 2 ? pair.1 | 0x40 : pair.1)
        }, "Audio Relay must preserve every unrelated bit, including firmware extension bytes")
        try expect(try RadioMaintenanceCodec.settingAudioRelay(false, in: enabled) == payload, "Turning Audio Relay off must restore the original payload exactly")
        try expect(try RadioMaintenanceCodec.settingAudioRelay(true, in: enabled) == enabled, "An unchanged Audio Relay value must be a no-op")
        for size in 0..<16 {
            try expectThrow("Truncated settings must not be patched") { _ = try RadioMaintenanceCodec.settingAudioRelay(true, in: payload.prefix(size)) }
        }
    }

    static func testSatelliteRetuning() throws {
        func target(rxHz: Int = 145_800_000, txHz: Int = 435_000_000, tone: Double? = nil) -> SatelliteRetuneTarget {
            SatelliteRetuneTarget(rxMHz: Double(rxHz) / 1_000_000, txMHz: Double(txHz) / 1_000_000,
                                 rxTone: nil, txTone: tone)!
        }
        var policy = SatelliteRetunePolicy()
        let initial = target()
        try expect(SatelliteRetunePolicy.defaultThresholdHz == 1_000, "Default retuning must not send tiny Doppler corrections every second")
        try expect(policy.shouldApply(initial, thresholdHz: 1_000, holdDuringReceive: true, isReceiving: true), "Initial tuning must not be blocked by reception hold")
        policy.recordApplied(initial)
        for delta in [1, 100, 499, 999] {
            try expect(!policy.shouldApply(target(rxHz: 145_800_000 + delta), thresholdHz: 1_000,
                                           holdDuringReceive: false, isReceiving: false), "Sub-threshold RX drift must accumulate against the last applied target")
        }
        let rxDrift = target(rxHz: 145_801_000)
        let txDrift = target(txHz: 435_001_000)
        try expect(policy.shouldApply(rxDrift, thresholdHz: 1_000, holdDuringReceive: false, isReceiving: false), "Accumulated RX drift must retune at the threshold")
        try expect(policy.shouldApply(txDrift, thresholdHz: 1_000, holdDuringReceive: false, isReceiving: false), "TX-only drift must also trigger retuning")
        try expect(!policy.shouldApply(txDrift, thresholdHz: 1_000, holdDuringReceive: true, isReceiving: true), "Automatic frequency changes must defer during receive hold")
        try expect(policy.shouldApply(txDrift, thresholdHz: 1_000, holdDuringReceive: true, isReceiving: false), "Latest target must become eligible once reception ends")
        try expect(policy.shouldApply(target(rxHz: 145_800_001), thresholdHz: 1_000,
                                      holdDuringReceive: true, isReceiving: true, force: true), "Explicit manual tuning must bypass both deadband and hold")
        try expect(policy.shouldApply(target(tone: 67), thresholdHz: 1_000, holdDuringReceive: true, isReceiving: true), "Tone changes must apply immediately")
        try expect(!policy.shouldApply(initial, thresholdHz: 0, holdDuringReceive: false, isReceiving: false, force: true), "Identical targets must not send duplicate tuning commands")
        try expect(policy.shouldApply(target(rxHz: 145_800_001), thresholdHz: 0, holdDuringReceive: false, isReceiving: false), "Any Change must allow real one-hertz differences")
        policy.recordApplied(rxDrift)
        try expect(!policy.shouldApply(target(rxHz: 145_801_500), thresholdHz: 1_000, holdDuringReceive: false, isReceiving: false), "Successful tuning must reset the drift baseline")
        policy.reset()
        try expect(policy.shouldApply(rxDrift, thresholdHz: 1_000, holdDuringReceive: false, isReceiving: false), "A new tracking or connection session must tune again")
        for invalid in [Double.nan, .infinity, -1, 1073.741824, 1073.7418239] {
            try expect(SatelliteRetuneTarget(rxMHz: invalid, txMHz: 435, rxTone: nil, txTone: nil) == nil, "Invalid and overflowing frequency targets must fail before command encoding")
        }
        try expect(SatelliteRetuneTarget(rxMHz: 145, txMHz: 435, rxTone: .nan, txTone: nil) == nil, "Invalid tones must not reach the radio")

        let source = try String(contentsOfFile: "FieldHT/ViewModels/SatelliteTrackingViewModel.swift", encoding: .utf8)
        try expect(!source.contains("syncActiveVFOForSatelliteMode"), "Native satellite retunes must not also write VFO memories")
        try expect(source.contains("radioManager.radioController === request.controller"), "Pending retunes must not leak across a reconnect")
        try expect(source.contains("retunePolicy.recordApplied(request.target)"), "Retune baseline must only advance after a successful radio command")
    }

    static func testFrequencyRangeDecoding() throws {
        let bands = Data([0x40, 0x6C, 0x40, 0x88, 0x80, 0x88, 0, 0xAE,
                          0x01, 0x2C, 0x02, 0x26, 0x81, 0x90, 0x02, 0x08])
        let ranges = try ProtocolDecoder.decodeFrequencyRanges(bands)
        try expect(ranges.ranges.contains(.init(lowerMHz: 108, upperMHz: 136, direction: .receive, modulation: .am)), "Airband must decode as AM receive")
        try expect(ranges.ranges.contains(.init(lowerMHz: 136, upperMHz: 174, direction: .transmit, modulation: .fm)), "Capability value 2 must decode as FM transmit, not DMR")
        try expect(!ranges.ranges.contains { $0.modulation == .dmr }, "FM band capability flags must not imply DMR support")
        let amWithoutHighTag = try ProtocolDecoder.decodeFrequencyRanges(Data([0x40, 0x6C, 0, 0x88]))
        try expect(amWithoutHighTag.ranges == [.init(lowerMHz: 108, upperMHz: 136, direction: .receive, modulation: .am)], "AM capability must come from the low edge even when the high edge has no flags")
        let fmWithHighTag = try ProtocolDecoder.decodeFrequencyRanges(Data([0, 0x88, 0xC0, 0xAE]))
        try expect(fmWithHighTag.ranges == [.init(lowerMHz: 136, upperMHz: 174, direction: .receive, modulation: .fm)], "High-edge flag bits must not invent AM transmit or receive capability")
        let wideEdges = try ProtocolDecoder.decodeFrequencyRanges(Data([0x83, 0x84, 0x04, 0x1A]))
        try expect(wideEdges.receiveFMRanges.first?.upperMHz == 1050, "Band edges must preserve all fourteen frequency bits")

        let terminator = Data([0x40, 0, 0, 0])
        let trailingBand = Data([0x82, 0x58, 0x02, 0xBC])
        let terminated = try ProtocolDecoder.decodeFrequencyRanges(bands + terminator + trailingBand)
        try expect(terminated == ranges, "Bytes after the zero-frequency terminator must not add supported bands")

        let zeroWidth = Data([0, 0xC8, 0, 0xC8])
        try expect(try ProtocolDecoder.decodeFrequencyRanges(zeroWidth + bands) == ranges, "Zero-width placeholders must not hide later supported bands")
        let reversed = Data([0x81, 0xE0, 0x01, 0x90])
        try expect(try ProtocolDecoder.decodeFrequencyRanges(bands + reversed + trailingBand) == ranges, "An inverted band must stop parsing untrusted trailing entries")
        try expectThrow("Truncated frequency bands must fail") { _ = try ProtocolDecoder.decodeFrequencyRanges(Data([0x80, 0x88, 0])) }
    }

    static func testFrequencyValidation() throws {
        let ranges = DeviceFrequencyRanges(ranges: [
            .init(lowerMHz: 136, upperMHz: 174, direction: .receive, modulation: .fm),
            .init(lowerMHz: 144, upperMHz: 148, direction: .transmit, modulation: .fm),
            .init(lowerMHz: 108, upperMHz: 136, direction: .receive, modulation: .am)
        ])
        var channel = try fixtureChannel(0)
        try expect(ChannelFrequencyValidator.issues(for: channel, ranges: ranges).isEmpty, "A supported duplex channel must pass")
        channel.txFreq = 170
        try expect(ChannelFrequencyValidator.issues(for: channel, ranges: ranges).count == 1, "Receive support must not imply transmit support")
        channel.txDisable = true
        try expect(ChannelFrequencyValidator.issues(for: channel, ranges: ranges).isEmpty, "Receive-only memories must not require a supported TX band")
        channel.txFreq = .nan
        try expect(!ChannelFrequencyValidator.issues(for: channel, ranges: ranges).isEmpty, "Even disabled TX must reject NaN before encoding")
        channel.txFreq = 0
        channel.rxFreq = 125
        channel.rxMod = .am
        try expect(ChannelFrequencyValidator.issues(for: channel, ranges: ranges).isEmpty, "AM receive ranges must retain their modulation")
        channel.rxMod = .fm
        try expect(!ChannelFrequencyValidator.issues(for: channel, ranges: ranges).isEmpty, "AM-only bands must not accept FM")
        channel.rxFreq = 0
        try expect(ChannelFrequencyValidator.issues(for: channel, ranges: ranges).isEmpty, "Empty slots must remain writable")
    }

    static func testFirmwareProtocol() throws {
        let request = try FirmwareUpdateService.request(productID: 259)
        try expect(request.url?.port == 800 && request.url?.scheme == "https", "Firmware checks must use the verified TLS endpoint")
        try expect(request.httpBody == Data([0, 0, 0, 0, 3, 8, 0x83, 2]), "Firmware request must encode the radio's product ID and omit zero/false proto3 fields")
        try expectThrow("No radio must not use a hardcoded product") { _ = try FirmwareUpdateService.request(productID: 0) }
        let descriptor = Data([8, 0x93, 1, 0x22, 6]) + Data("stable".utf8) + Data([0x28, 0xAC, 2])
        let result = Data([0x0A, UInt8(descriptor.count)]) + descriptor
        let frame = Data([0, 0, 0, 0, UInt8(result.count)]) + result
        let update = try FirmwareUpdateService.decodeResponse(frame)
        try expect(update?.version == 147 && update?.releaseNotes == "stable" && update?.releaseDate == Date(timeIntervalSince1970: 300), "Firmware descriptor fields must decode correctly")
        for size in 0..<frame.count {
            try expectThrow("Truncated gRPC responses must fail") { _ = try FirmwareUpdateService.decodeResponse(Data(frame.prefix(size))) }
        }
        try expect(try FirmwareUpdateService.decodeResponse(Data([0, 0, 0, 0, 0])) == nil, "An empty protobuf result means no published firmware")
        try expectThrow("Malformed protobuf lengths must fail") { _ = try FirmwareUpdateService.decodeResponse(Data([0, 0, 0, 0, 2, 0x0A, 0x7F])) }
        try expectThrow("Compressed gRPC must not be treated as plaintext") { _ = try FirmwareUpdateService.decodeResponse(Data([1, 0, 0, 0, 0])) }
    }

    static func testBackupCaptureAndRestore() async throws {
        let radio = try FakeRadio()
        radio.region = 0
        let backup = try await RadioBackupService.capture(from: radio) { _, _ in }
        try expect(radio.region == 0 && radio.ended == 1, "Capture must return to the original group and release its operation")
        try expect(backup.regions.count == 2 && backup.regions.allSatisfy { $0.channels.count == 2 } && backup.vfoChannels.count == 2, "Capture must include every group, memory, and VFO")
        let decoded = try RadioBackup.decode(backup.encoded())
        try expect(decoded.settingsPayload == backup.settingsPayload, "Unknown raw settings bytes must survive file export/import")
        try expect(decoded.beaconPayload == backup.beaconPayload && decoded.aprsPath == "WIDE1-1" && decoded.programmableButtons == radio.buttons, "Beacon settings, paths, and buttons must survive export/import")
        try await RadioBackupService.restore(decoded, to: radio) { _, _ in }
        try expect(radio.writes == 6 && radio.region == 0 && radio.ended == 2, "Restore must write all six channels and return to the starting group")
        try expect(radio.writtenSettings == backup.settingsPayload, "Restore must preserve the exact settings payload")
        try expect(radio.settingsWriteRegion == 0, "Global active-channel settings must be applied in the original group")
    }

    static func testBackupFailures() async throws {
        let source = try FakeRadio()
        let backup = try await RadioBackupService.capture(from: source) { _, _ in }
        let other = try FakeRadio(productID: 260)
        do {
            try await RadioBackupService.restore(backup, to: other) { _, _ in }
            throw TestFailure(message: "Mismatched radios must fail")
        } catch is RadioBackupError {}
        try expect(other.begun == 0 && other.writes == 0, "Incompatible backups must fail before any operation or write")

        var json = try JSONSerialization.jsonObject(with: backup.encoded()) as! [String: Any]
        json["version"] = 99
        try expectThrow("Future formats must not silently restore") { _ = try RadioBackup.decode(JSONSerialization.data(withJSONObject: json)) }
        json["version"] = 1
        json["regions"] = []
        try expectThrow("Incomplete backups must fail") { _ = try RadioBackup.decode(JSONSerialization.data(withJSONObject: json)) }

        let failing = try FakeRadio()
        failing.failWrite = true
        do {
            try await RadioBackupService.restore(backup, to: failing) { _, _ in }
            throw TestFailure(message: "Write failure must be reported")
        } catch is RadioBackupError {}
        try expect(failing.region == 1 && failing.ended == 1 && failing.writtenSettings == nil, "Failed restore must clean up the group and stop before global settings")

        let corruptReadback = try FakeRadio()
        corruptReadback.corruptReadback = true
        do {
            try await RadioBackupService.restore(backup, to: corruptReadback) { _, _ in }
            throw TestFailure(message: "Unverified writes must stop the restore")
        } catch is RadioBackupError {}
        try expect(corruptReadback.writes == 1 && corruptReadback.region == 1, "Readback mismatch must stop immediately and restore the group")

        let unsupported = try FakeRadio()
        unsupported.rejectFrequencies = true
        do {
            try await RadioBackupService.restore(backup, to: unsupported) { _, _ in }
            throw TestFailure(message: "Unsupported frequencies must prevent restore")
        } catch is RadioBackupError {}
        try expect(unsupported.writes == 0 && unsupported.region == 1 && unsupported.ended == 1, "Frequency preflight must finish before any restore write")

        let cancelled = try FakeRadio()
        cancelled.cancelRead = true
        do {
            _ = try await RadioBackupService.capture(from: cancelled) { _, _ in }
            throw TestFailure(message: "Cancellation must propagate")
        } catch is CancellationError {}
        try expect(cancelled.region == 1 && cancelled.ended == 1, "Cancelled capture must still restore the original group")
    }

    static func fixtureChannel(_ slot: Int) throws -> Channel {
        var channel = try ProtocolDecoder.decodeChannel(Data(repeating: 0, count: 25))
        channel.channelID = slot
        channel.name = "TEST"
        channel.rxFreq = 146.52
        channel.txFreq = 146.52
        return channel
    }
}

private struct TestFailure: Error { let message: String }

@MainActor
private final class FakeRadio: RadioBackupTransport {
    let deviceInfo: DeviceInfo
    var region = 1
    var begun = 0
    var ended = 0
    var writes = 0
    var writtenSettings: Data?
    var settingsWriteRegion: Int?
    var failWrite = false
    var corruptReadback = false
    var cancelRead = false
    var rejectFrequencies = false
    var beacon = ProtocolEncoder.encodeBeaconSettings(.empty())
    var path = "WIDE1-1"
    var buttons = PFConfig(pf: [PF(buttonID: 1, action: .short, effect: PFEffectType(rawValue: 12))])
    var channels: [Int: [Int: Channel]] = [:]

    init(productID: Int = 259) throws {
        deviceInfo = DeviceInfo(vendorID: 1, productID: productID, hardwareVersion: 1, firmwareVersion: 147,
            supportsRadio: true, supportsMediumPower: false, fixedLocationSpeakerVolume: false,
            supportsSoftwarePowerControl: true, hasSpeaker: true, hasHandMicrophoneSpeaker: true,
            regionCount: 2, supportsNOAA: true, supportsGMRS: false, supportsVFO: true, supportsDMR: false,
            channelCount: 2, frequencyRangeCount: 0, supportsSmartBeacon: true)
        for region in 0..<2 {
            for slot in [0, 1, 251, 252] { channels[region, default: [:]][slot] = try RadioToolsTests.fixtureChannel(slot) }
        }
    }
    func beginBackupOperation() async throws { begun += 1 }
    func endBackupOperation() { ended += 1 }
    func backupRegion() async throws -> Int { region }
    func selectBackupRegion(_ index: Int) async throws { region = index }
    func readBackupChannel(_ slot: Int) async throws -> Channel {
        if cancelRead { throw CancellationError() }
        var channel = channels[region]![slot]!
        if corruptReadback { channel.rxFreq = 145 }
        return channel
    }
    func writeBackupChannel(_ channel: Channel, region: Int?) async throws {
        writes += 1
        if failWrite { throw TestFailure(message: "Simulated write failure") }
        channels[region ?? self.region, default: [:]][channel.channelID] = channel
    }
    func readBackupRegionName(_ index: Int) async throws -> String { "Group \(index + 1)" }
    func writeBackupRegionName(_ name: String, index: Int) async throws {}
    func readBackupSettings() async throws -> Data {
        if let writtenSettings { return writtenSettings }
        var settings = Settings.empty()
        settings.rawExtensionData = Data([0xAA, 0x55])
        return ProtocolEncoder.encodeSettings(settings)
    }
    func writeBackupSettings(_ data: Data) async throws { writtenSettings = data; settingsWriteRegion = region }
    func readBackupBeacon() async throws -> Data? { beacon }
    func writeBackupBeacon(_ data: Data) async throws { beacon = data }
    func readBackupPath() async throws -> String? { path }
    func writeBackupPath(_ path: String) async throws { self.path = path }
    func readBackupButtons() async throws -> PFConfig? { buttons }
    func writeBackupButtons(_ config: PFConfig) async throws { buttons = config }
    func validateBackupChannels(_ channels: [Channel]) async throws {
        if rejectFrequencies { throw RadioBackupError.invalidFile("Unsupported test frequencies") }
    }
}
