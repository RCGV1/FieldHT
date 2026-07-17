import Foundation

@main
struct QuickChannelScanTests {
    static func main() throws {
        let source = try readSource("FieldHT/ViewModels/RadioManager.swift")

        try expect(source.contains("try await controller.toggleScan()"),
                   "Quick Scan must use the radio's dedicated channel-scan action.")
        try expect(!source.contains("updatedSettings.scan = shouldScan"),
                   "Quick Scan must not fake scanning by only rewriting the settings bit.")
        try expect(!source.contains("try await controller.setRadioMode(0)"),
                   "Quick Scan must not force the radio into a different mode.")
        try expect(source.contains("radioController?.state?.status.isScan ?? radioController?.state?.settings.scan"),
                   "The scan indicator must prefer the radio's live scan state over stored settings.")
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
