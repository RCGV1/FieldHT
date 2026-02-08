import Foundation
import CoreLocation

#if canImport(SatelliteKit)
import SatelliteKit
#endif

struct SatPass: Equatable {
    let startUTC: Int
    let maxEl: Double
    let maxUTC: Int
    let endUTC: Int
}

enum SatPassError: Error, LocalizedError {
    case sgp4Unavailable
    case noPassFound
    case invalidObserver

    var errorDescription: String? {
        switch self {
        case .sgp4Unavailable:
            return "Pass predictions unavailable (SatelliteKit not linked)"
        case .noPassFound:
            return "No visible pass found in the given time window"
        case .invalidObserver:
            return "Invalid observer location"
        }
    }
}

enum SatPassPredictor {
    private static let minElevationDeg: Double = 0.0
    private static let timeStepSeconds: Int = 10

    static func nextPass(
        tle: TLERecord,
        observer: CLLocation,
        days: Int = 3,
        minElevation: Double = 5.0
    ) async throws -> SatPass? {
#if canImport(SatelliteKit)
        guard observer.altitude >= 0 else {
            throw SatPassError.invalidObserver
        }

        let obs = LatLonAlt(
            observer.coordinate.latitude,
            observer.coordinate.longitude,
            observer.altitude / 1000.0
        )

        let elements = try Elements(tle.name, tle.line1, tle.line2)
        let sat = Satellite(withTLE: elements)

        let now = Date()
        let endDate = now.addingTimeInterval(Double(days) * 24 * 3600)

        var bestPass: SatPass?
        var searchingForAOS = true

        var t = now
        var lastEl: Double = -90.0
        var aosTime: Date?
        var losTime: Date?

        while t < endDate {
            let mins = sat.minsAfterEpoch + (t.timeIntervalSince1970 - now.timeIntervalSince1970) / 60.0
            let top = try? sat.topPosition(minsAfterEpoch: mins, observer: obs)
            let el = top?.elev ?? -90.0

            if searchingForAOS {
                if el > minElevation && lastEl <= minElevation {
                    searchingForAOS = false
                    aosTime = t
                }
            } else {
                if el > maxEl {
                    maxEl = el
                    maxUTC = Int(t.timeIntervalSince1970)
                }
                if el < minElevation && lastEl >= minElevation {
                    losTime = t
                    let startUTC = Int(aosTime?.timeIntervalSince1970 ?? 0)
                    let endUTC = Int(losTime?.timeIntervalSince1970 ?? 0)
                    bestPass = SatPass(
                        startUTC: startUTC,
                        maxEl: maxEl,
                        maxUTC: maxUTC,
                        endUTC: endUTC
                    )
                    break
                }
            }

            lastEl = el
            t = t.addingTimeInterval(Double(timeStepSeconds))
        }

        return bestPass
#else
        throw SatPassError.sgp4Unavailable
#endif
    }

    private static var maxEl: Double = 0.0
    private static var maxUTC: Int = 0
}
