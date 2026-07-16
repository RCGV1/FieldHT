import Foundation

@main
enum FrequencyScanCapabilityTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let constants = try String(contentsOf: root.appending(path: "FieldHT/Protocol/ProtocolConstants.swift"), encoding: .utf8)
        let message = try String(contentsOf: root.appending(path: "FieldHT/Command/RadioMessage.swift"), encoding: .utf8)
        let event = try String(contentsOf: root.appending(path: "FieldHT/Command/EventMessage.swift"), encoding: .utf8)
        let decoder = try String(contentsOf: root.appending(path: "FieldHT/Protocol/ProtocolDecoder.swift"), encoding: .utf8)
        let connection = try String(contentsOf: root.appending(path: "FieldHT/Command/CommandConnection.swift"), encoding: .utf8)
        let controller = try String(contentsOf: root.appending(path: "FieldHT/RadioController.swift"), encoding: .utf8)
        let manager = try String(contentsOf: root.appending(path: "FieldHT/ViewModels/RadioManager.swift"), encoding: .utf8)
        let scan = try String(contentsOf: root.appending(path: "FieldHT/Views/AdvancedFrequencyScanView.swift"), encoding: .utf8)

        var failures = 0

        func expect(_ condition: Bool, _ message: String) {
            if !condition {
                failures += 1
                fputs("FAIL: \(message)\n", stderr)
            }
        }

        expect(constants.contains("frequencyScanStatusChanged = 14"), "the stock frequency-scan status event must be modeled")
        expect(message.contains("case frequencyRanges"), "the radio message model must carry parsed device frequency ranges")
        expect(event.contains("case frequencyModeStatus"), "scan status notifications must be decoded as typed events")
        expect(decoder.contains("decodeFrequencyRanges"), "the protocol decoder must parse command-39 frequency ranges")
        expect(connection.contains("getFrequencyRanges"), "the command connection must read command-39 ranges")
        expect(connection.contains("case .frequencyScanStatusChanged"), "the command connection must decode frequency-scan status notifications")
        expect(controller.contains("frequencyScanStatus"), "the radio controller must publish live scan status notifications")
        expect(controller.contains("getFrequencyRanges"), "the radio controller must expose device frequency ranges")
        expect(controller.contains("rxSubAudio: SubAudio?"), "frequency scan commands must accept the current receive tone")
        expect(manager.contains("rxSubAudio: SubAudio?"), "the radio manager must forward the current receive tone")
        expect(scan.contains("loadSupportedRanges"), "advanced scan must load the radio's supported frequency ranges")
        expect(scan.contains("isNotificationSupported"), "advanced scan must prefer capability-gated status notifications")
        expect(scan.contains("rxSubAudio: currentReceiveTone"), "advanced scan must preserve the current receive tone in radio commands")
        expect(scan.contains("txSubAudio: currentTransmitTone"), "advanced scan must preserve the current transmit tone in radio commands")
        expect(scan.contains("let initialStatus = try await radioManager.getFrequencyScanStatus()"), "advanced scan must seed tone values from the radio before scanning")

        if failures > 0 {
            exit(1)
        }

        print("FrequencyScanCapabilityTests passed")
    }
}
