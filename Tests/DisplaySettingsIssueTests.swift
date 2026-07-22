import Foundation

@main
enum DisplaySettingsIssueTests {
    static func main() throws {
        let app = try readSource("FieldHT/FieldHTApp.swift")
        let settings = try readSource("FieldHT/Views/SettingsView.swift")

        try expect(!app.contains("FieldHT.appBrightness"), "FieldHT must not present an app-only brightness slider as a radio setting.")
        try expect(!settings.contains("App Brightness"), "Display settings must not contain the unsupported app-brightness control.")
        try expect(settings.contains("Radio Screen Timeout"), "The verified radio display setting must be labelled as radio-specific.")
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
