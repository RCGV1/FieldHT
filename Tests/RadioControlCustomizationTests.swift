import Foundation

@main
enum RadioControlCustomizationTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let layoutURL = root.appending(path: "FieldHT/Models/RadioControlLayout.swift")
        let radioControlURL = root.appending(path: "FieldHT/Views/RadioControlView.swift")
        let settingsURL = root.appending(path: "FieldHT/Views/SettingsView.swift")
        var failures = 0

        func expect(_ condition: Bool, _ message: String) {
            if !condition {
                failures += 1
                fputs("FAIL: \(message)\n", stderr)
            }
        }

        expect(FileManager.default.fileExists(atPath: layoutURL.path), "radio control layout must be stored locally")

        if let layout = try? String(contentsOf: layoutURL, encoding: .utf8) {
            expect(layout.contains("case primaryChannels"), "primary Channel A/B controls must be represented in the default layout")
            expect(layout.contains("case .primaryChannels: return false"), "primary Channel A/B controls must not be removable")
            expect(layout.contains("UserDefaults.standard"), "radio control layout must persist across launches")
        }

        let radioControl = try String(contentsOf: radioControlURL, encoding: .utf8)
        expect(radioControl.contains("ForEach(radioControlLayout.sections"), "radio control must render the user's ordered layout")

        let settings = try String(contentsOf: settingsURL, encoding: .utf8)
        expect(settings.contains("Customize Radio Control"), "settings must expose radio control customization")

        if failures > 0 {
            exit(1)
        }

        print("RadioControlCustomizationTests passed")
    }
}
