import Foundation

@main
struct APRSSettingsIssueTests {
    static func main() throws {
        let beaconView = try readSource("FieldHT/Views/BeaconSettingsView.swift")
        let manager = try readSource("FieldHT/ViewModels/RadioManager.swift")
        let settings = try readSource("FieldHT/Models/Settings.swift")
        let connection = try readSource("FieldHT/Command/CommandConnection.swift")
        let encoder = try readSource("FieldHT/Protocol/ProtocolEncoder.swift")

        try expect(beaconView.contains("Enable BSS / APRS"), "Digital modes need an explicit enable switch.")
        try expect(beaconView.contains("Packet Format"), "APRS and BSS need a clear format selector.")
        try expect(beaconView.contains("KISS TNC"), "APRS settings need a KISS TNC switch.")
        try expect(beaconView.contains("Transmit Channel"), "APRS settings need a dedicated transmit channel.")
        try expect(beaconView.contains("Location Beaconing"), "Location controls should be grouped together.")
        try expect(beaconView.contains("Enable Smart Beacon"), "APRS settings need Smart Beacon controls.")
        try expect(manager.contains("setDigitalSignalEnabled"), "RadioManager must expose digital-mode control.")
        try expect(manager.contains("setKISSTNCEnabled"), "RadioManager must expose KISS control.")
        try expect(manager.contains("setAutoShareLocationChannel"), "RadioManager must expose a beacon channel setter.")
        try expect(settings.contains("var kissEnabled"), "Settings must model the KISS enabled bit.")
        try expect(encoder.contains("autoShareLocChRaw & 0x1F"), "Beacon channel writes must preserve the low channel bits.")
        try expect(encoder.contains("(autoShareLocChRaw >> 5) & 0x07"), "Beacon channel writes must preserve the upper channel bits.")
        try expect(connection.contains("setDigitalSignalEnabled"), "The connection must send digital-mode commands.")
        try expect(encoder.contains("encodeSetIsDigitalSignal"), "The protocol must encode digital-mode commands.")
    }

    private static func readSource(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path), encoding: .utf8)
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw TestFailure(message: message) }
    }
}

private struct TestFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
