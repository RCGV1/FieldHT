import Foundation

@main
enum RadioManagerReconnectReuseTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = try String(
            contentsOf: root.appending(path: "FieldHT/ViewModels/RadioManager.swift"),
            encoding: .utf8
        )
        let start = try requireIndex(of: "    public func disconnect() {")
        let end = try requireIndex(of: "    /// Called by the BLE layer", after: start)
        let disconnect = String(source[start..<end])
        var failures = 0

        func expect(_ condition: Bool, _ message: String) {
            if !condition {
                failures += 1
                fputs("FAIL: \(message)\n", stderr)
            }
        }

        expect(!disconnect.contains("self.connectionController = nil"), "manual disconnect must retain the BLE controller for reconnect")
        expect(!disconnect.contains("self.connectionControllerDeviceUUID = nil"), "manual disconnect must retain the saved controller identity")

        if failures > 0 {
            exit(1)
        }

        print("RadioManagerReconnectReuseTests passed")
    }

    private static func requireIndex(of text: String, after: String.Index? = nil) throws -> String.Index {
        let range = sourceRange(for: text, after: after)
        guard let range else {
            throw NSError(domain: "RadioManagerReconnectReuseTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing expected source marker: \(text)"])
        }
        return range.lowerBound
    }

    private static func sourceRange(for text: String, after: String.Index?) -> Range<String.Index>? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        guard let source = try? String(contentsOf: root.appending(path: "FieldHT/ViewModels/RadioManager.swift"), encoding: .utf8) else {
            return nil
        }
        return source.range(of: text, range: after.map { $0..<source.endIndex })
    }
}
