import Foundation

@main
enum SettingsDigitalModeTests {
    static func main() {
        var failures = 0

        func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
            if actual != expected {
                failures += 1
                fputs("FAIL: \(message). Expected \(expected), got \(actual)\n", stderr)
            }
        }

        var settings = Settings.empty()
        settings.kissEnabled = true
        expectEqual(settings.vfoX, 0b01, "KISS enabled uses the low protocol bit")
        expectEqual(settings.kissUploadTxMessage, false, "KISS upload remains unchanged")

        settings.kissUploadTxMessage = true
        expectEqual(settings.vfoX, 0b11, "KISS upload preserves the KISS enabled bit")
        expectEqual(settings.kissEnabled, true, "KISS enabled round trips")

        settings.kissEnabled = false
        expectEqual(settings.vfoX, 0b10, "disabling KISS preserves the upload bit")

        if failures > 0 {
            exit(1)
        }

        print("SettingsDigitalModeTests passed")
    }
}
