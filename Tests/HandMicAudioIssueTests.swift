import Foundation

@main
struct HandMicAudioIssueTests {
    static func main() throws {
        let speakerMicView = try readSource("FieldHT/Views/SpeakerMicView.swift")
        let settings = try readSource("FieldHT/Models/Settings.swift")
        let viewModel = try readSource("FieldHT/ViewModels/SettingsViewModel.swift")
        let encoder = try readSource("FieldHT/Protocol/ProtocolEncoder.swift")
        let decoder = try readSource("FieldHT/Protocol/ProtocolDecoder.swift")

        try expect(speakerMicView.contains("Prompt & Tone Volume"),
                   "The hand-mic page must expose the firmware prompt and tone volume.")
        try expect(speakerMicView.contains("Mute Channel Announcements & Tones"),
                   "The hand-mic page must expose an explicit announcement mute switch.")
        try expect(settings.contains("var alarmVolume"),
                   "Settings must model the firmware alarm volume field.")
        try expect(viewModel.contains("updateAlarmVolume"),
                   "The settings view model must persist hand-mic prompt volume.")
        try expect(encoder.contains("settings.alarmVolume, bitCount: 4"),
                   "The encoder must write alarm volume at its four-bit protocol position.")
        try expect(decoder.contains("let alarmVolume = try stream.readInt(4)"),
                   "The decoder must read alarm volume from the settings tail.")
    }

    private static func readSource(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw TestFailure(message: message) }
    }
}

private struct TestFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
