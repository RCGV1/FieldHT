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
            RadioPresentation.channelMenuLabel(channelID: 0, name: "  Local Repeater  "),
            "1. Local Repeater",
            "channel menu labels include the channel number and trimmed name"
        )
        expectEqual(
            RadioPresentation.channelMenuLabel(channelID: 4, name: ""),
            "5. Unnamed channel",
            "blank channel names use a clear fallback"
        )
        expectEqual(
            RadioPresentation.screenTimeoutOptions.map(\.label),
            ["Always On", "5 seconds", "10 seconds", "15 seconds", "20 seconds", "25 seconds", "300 seconds (Max)"],
            "screen timeout uses the radio's encoded choices through its 300-second maximum"
        )
        expectEqual(
            RadioPresentation.txHoldOptions.map(\.label),
            ["Off", "0.1 seconds", "0.2 seconds", "0.3 seconds", "0.4 seconds", "0.5 seconds", "0.6 seconds", "0.7 seconds", "0.8 seconds", "0.9 seconds", "1.0 seconds"],
            "TX hold uses the radio's tenth-of-a-second steps"
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
        expectEqual(
            PFEffectType.toggleOffline.displayName,
            "Toggle Talk Around",
            "talk-around effect uses radio terminology"
        )
        expectEqual(
            PFEffectType.prevRegion.displayName,
            "Previous Group",
            "group navigation is not labeled as a region"
        )

        if failures > 0 {
            exit(1)
        }

        print("RadioPresentationTests passed")
    }
}
