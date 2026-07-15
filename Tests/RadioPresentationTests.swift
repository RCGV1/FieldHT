import Foundation

@main
enum RadioPresentationTests {
    static func main() {
        var failures = 0

        func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
            if actual != expected {
                failures += 1
                fputs("FAIL: \(message). Expected \(expected), got \(actual)\n", stderr)
            }
        }

        expectEqual(RadioPresentation.sMeterLabel(forPercent: 0), "S0", "0% is S0")
        expectEqual(RadioPresentation.sMeterLabel(forPercent: 50), "S5", "50% is S5")
        expectEqual(RadioPresentation.sMeterLabel(forPercent: 100), "S9+", "100% is S9+")
        expectEqual(RadioPresentation.sMeterLabel(forPercent: -1), "S0", "signal clamps below zero")
        expectEqual(RadioPresentation.sMeterLabel(forPercent: 200), "S9+", "signal clamps above 100")
        expectEqual(
            RadioPresentation.screenTimeoutOptions.contains { $0.value > 31 },
            false,
            "screen timeout options must fit the current five-bit field"
        )
        expectEqual(
            RadioPresentation.txLimitOptions.allSatisfy { (0...31).contains($0.value) },
            true,
            "time-out timer options must fit the current five-bit field"
        )
        expectEqual(
            RadioPresentation.speakerMicName(model: nil, isBS22: false),
            "Speaker Mic",
            "unknown accessory uses generic copy"
        )

        if failures > 0 {
            exit(1)
        }

        print("RadioPresentationTests passed")
    }
}
