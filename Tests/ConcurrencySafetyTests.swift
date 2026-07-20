import Foundation

@main
enum ConcurrencySafetyTests {
    static func main() throws {
        requireSendable(DCS.self)
        requireSendable(SubAudio.self)

        let importerURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "FieldHT/Services/AIChannelImporter.swift")
        let importer = try String(contentsOf: importerURL, encoding: .utf8)
        precondition(
            importer.contains("private nonisolated static func normalizeHeaderLabel"),
            "CSV header normalization must stay callable off the main actor"
        )

        print("ConcurrencySafetyTests passed")
    }

    private static func requireSendable<T: Sendable>(_: T.Type) {}
}
