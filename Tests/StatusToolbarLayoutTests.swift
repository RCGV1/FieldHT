import Foundation

@main
enum StatusToolbarLayoutTests {
    static func main() throws {
        let sourceURL = URL(fileURLWithPath: "FieldHT/Views/GlobalStatusToolbar.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        var failures = 0

        func expect(_ condition: Bool, _ message: String) {
            if !condition {
                failures += 1
                fputs("FAIL: \(message)\n", stderr)
            }
        }

        expect(
            !source.contains("Text(\"\\(radioManager.hmBatteryLevel)%\")"),
            "speaker mic battery must not consume text width in the global status pill"
        )
        expect(
            !source.contains("Text(\"BT Audio\")"),
            "Bluetooth audio must not consume text width in the global status pill"
        )

        if failures > 0 {
            exit(1)
        }

        print("StatusToolbarLayoutTests passed")
    }
}
