import Foundation

// Shared state used to drive the Satellite Live Activity.
// Kept free of ActivityKit/WidgetKit so the app can compile everywhere.
struct SatelliteActivityState: Codable, Hashable {
    var name: String

    var azDeg: Int
    var elDeg: Int
    var rangeKm: Int

    var dopplerShiftHz: Int
    var rxMHzX1000: Int
    var txMHzX1000: Int

    var source: String
    var countdown: String?
    var updatedAtUnix: Int
}
