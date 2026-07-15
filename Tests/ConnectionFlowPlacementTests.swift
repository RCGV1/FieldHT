import Foundation

@main
enum ConnectionFlowPlacementTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let settings = try String(contentsOf: root.appending(path: "FieldHT/Views/SettingsView.swift"), encoding: .utf8)
        let connect = try String(contentsOf: root.appending(path: "FieldHT/Views/ConnectView.swift"), encoding: .utf8)
        var failures = 0

        func expect(_ condition: Bool, _ message: String) {
            if !condition {
                failures += 1
                fputs("FAIL: \(message)\n", stderr)
            }
        }

        expect(!settings.contains("Connection Management"), "Settings must not expose connection management")
        expect(!settings.contains("ConnectionManagementView"), "Settings must not route into connection management")
        expect(connect.contains("Reconnect Automatically"), "Connect must own automatic reconnect")
        expect(connect.contains("forgetSavedRadio"), "Connect must own saved-radio removal")

        if failures > 0 {
            exit(1)
        }

        print("ConnectionFlowPlacementTests passed")
    }
}
