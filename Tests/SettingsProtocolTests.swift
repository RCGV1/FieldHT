import Foundation

enum ProtocolError: Error {
    case invalidCommandGroup
    case invalidPowerStatusType
    case decodeError(String)
}

@main
enum SettingsProtocolTests {
    static func main() {
        var failures = 0

        func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
            if actual != expected {
                failures += 1
                fputs("FAIL: \(message). Expected \(expected), got \(actual)\n", stderr)
            }
        }

        var settings = Settings.empty()
        settings.autoShareLocCh = 200
        settings.kissEnabled = true
        settings.kissUploadTxMessage = true

        do {
            let decoded = try ProtocolDecoder.decodeSettings(ProtocolEncoder.encodeSettings(settings))
            expectEqual(decoded.autoShareLocCh, 200, "beacon transmit channel preserves all eight bits")
            expectEqual(decoded.kissEnabled, true, "KISS enabled survives a settings round trip")
            expectEqual(decoded.kissUploadTxMessage, true, "KISS upload survives a settings round trip")
        } catch {
            failures += 1
            fputs("FAIL: settings payload should round trip: \(error)\n", stderr)
        }

        if failures > 0 {
            exit(1)
        }

        print("SettingsProtocolTests passed")
    }
}
