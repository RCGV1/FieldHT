import Foundation

@main
enum BeaconTimingPolicyTests {
    static func main() {
        var failures = 0

        func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
            guard actual == expected else {
                failures += 1
                fputs("FAIL: \(message). Expected \(expected), got \(actual)\n", stderr)
                return
            }
        }

        expectEqual(BeaconTimingPolicy.normalizedBaseInterval(0, isBeaconingEnabled: true), 300, "enabled beaconing defaults to five minutes instead of zero")
        expectEqual(BeaconTimingPolicy.normalizedBaseInterval(0, isBeaconingEnabled: false), 0, "disabled beaconing remains off")
        expectEqual(BeaconTimingPolicy.normalizedBaseInterval(183, isBeaconingEnabled: true), 180, "base interval rounds to a supported radio interval")
        expectEqual(BeaconTimingPolicy.normalizedMaximumInterval(0), 30, "missing Smart Beacon maximum defaults to the stock app value")
        expectEqual(BeaconTimingPolicy.normalizedMaximumInterval(99), 30, "Smart Beacon maximum stays within the radio range")

        if failures > 0 {
            exit(1)
        }

        print("BeaconTimingPolicyTests passed")
    }
}
