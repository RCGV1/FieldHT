import Foundation

@main
enum SettingsOrganizationTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let settings = try String(contentsOf: root.appending(path: "FieldHT/Views/SettingsView.swift"), encoding: .utf8)
        let viewModel = try String(contentsOf: root.appending(path: "FieldHT/ViewModels/SettingsViewModel.swift"), encoding: .utf8)

        let expectedCategories = ["Radio Setup", "Audio", "Transmission", "Power", "Display"]
        for category in expectedCategories where !settings.contains("Label(\"\(category)\"") {
            throw SettingsOrganizationTestFailure(message: "Missing \(category) settings category")
        }

        for control in ["Enable VOX", "Sensitivity", "Radio Time Zone", "App Brightness"] where !settings.contains(control) {
            throw SettingsOrganizationTestFailure(message: "Missing \(control) control")
        }

        for update in ["updateVoxEnabled", "updateVoxLevel", "updateVoxDelay", "updateTimeOffset"] where !viewModel.contains(update) {
            throw SettingsOrganizationTestFailure(message: "Missing real settings update path for \(update)")
        }

        print("SettingsOrganizationTests passed")
    }
}

private struct SettingsOrganizationTestFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
