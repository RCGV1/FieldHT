import Foundation

/// Valid beacon timings accepted by the radio programmer. The radio stores the
/// base interval in ten-second units, and Smart Beacon uses that value as its
/// minimum interval.
enum BeaconTimingPolicy {
    static let baseIntervals = [
        0, 10, 20, 30, 40, 50, 60, 120, 180, 240, 300, 360, 420, 480,
        540, 600, 900, 1_200, 1_500, 1_800
    ]
    static let smartBeaconMaximumIntervals = Array(1...30)
    static let defaultInterval = 300

    static func normalizedBaseInterval(_ interval: Int, isBeaconingEnabled: Bool) -> Int {
        guard isBeaconingEnabled else { return 0 }
        guard interval > 0 else { return defaultInterval }

        return baseIntervals.dropFirst().min(by: {
            abs($0 - interval) < abs($1 - interval)
        }) ?? defaultInterval
    }

    static func normalizedMaximumInterval(_ interval: Int) -> Int {
        guard interval > 0 else { return smartBeaconMaximumIntervals.last ?? 30 }
        return min(max(interval, smartBeaconMaximumIntervals.first ?? 1), smartBeaconMaximumIntervals.last ?? 30)
    }

    static func label(for interval: Int) -> String {
        switch interval {
        case 0:
            return "Off"
        case 60... where interval % 60 == 0:
            let minutes = interval / 60
            let unit = minutes == 1 ? "minute" : "minutes"
            return "\(minutes) \(unit)"
        default:
            return "\(interval) seconds"
        }
    }
}
