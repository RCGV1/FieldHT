import Foundation

// Lives in the widget target so `Widget/WidgetLiveActivity.swift` can always see it.
// The app only references this behind `canImport(ActivityKit)` guards.
#if os(iOS) && !targetEnvironment(macCatalyst)
import ActivityKit

struct SatelliteTrackingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
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

        init(from state: SatelliteActivityState) {
            self.name = state.name
            self.azDeg = state.azDeg
            self.elDeg = state.elDeg
            self.rangeKm = state.rangeKm
            self.dopplerShiftHz = state.dopplerShiftHz
            self.rxMHzX1000 = state.rxMHzX1000
            self.txMHzX1000 = state.txMHzX1000
            self.source = state.source
            self.countdown = state.countdown
            self.updatedAtUnix = state.updatedAtUnix
        }
    }

    var satId: Int
}

#endif
