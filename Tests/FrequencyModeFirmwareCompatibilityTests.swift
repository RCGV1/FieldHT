import Foundation

@main
enum FrequencyModeFirmwareCompatibilityTests {
    static func main() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let message = try String(contentsOf: root.appendingPathComponent("FieldHT/Command/RadioMessage.swift"), encoding: .utf8)
        let controller = try String(contentsOf: root.appendingPathComponent("FieldHT/RadioController.swift"), encoding: .utf8)
        let encoder = try String(contentsOf: root.appendingPathComponent("FieldHT/Protocol/ProtocolEncoder.swift"), encoding: .utf8)

        try expect(message.contains("case noaa = 6"), "Frequency mode must model the OEM NOAA mode.")
        try expect(message.contains("case toneScan = 7"), "Frequency mode must model the OEM tone-scan mode without exposing unverified results.")
        try expect(controller.contains("firmwareVersion >= 137"), "Frequency-mode writes must select the payload length supported by the radio firmware.")
        try expect(encoder.contains("includeExtendedParameters"), "The frequency-mode encoder must support the pre-137 payload form.")
        try expect(encoder.contains("if includeExtendedParameters"), "The extension must only be emitted for firmware that supports it.")
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw TestFailure(message: message) }
    }
}

private struct TestFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
