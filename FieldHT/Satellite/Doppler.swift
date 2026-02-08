import Foundation
import CoreLocation

enum Doppler {
    static let speedOfLightMetersPerSecond = 299_792_458.0

    struct Correction {
        let rangeRateMetersPerSecond: Double
        let rxCorrectedHz: Double
        let txCorrectedHz: Double
    }

    // Returns Doppler-corrected frequencies based on line-of-sight range rate.
    // Convention: range rate > 0 means satellite is receding (range increasing).
    // Observed receive frequency decreases when receding: f_obs = f * (1 - v/c)
    // For uplink, pre-compensate so satellite receives nominal: f_tx = f * (1 + v/c)
    static func correction(nominalRxHz: Double, nominalTxHz: Double, rangeRateMetersPerSecond: Double) -> Correction {
        let vOverC = rangeRateMetersPerSecond / speedOfLightMetersPerSecond
        let rx = nominalRxHz * (1.0 - vOverC)
        let tx = nominalTxHz * (1.0 + vOverC)
        return Correction(rangeRateMetersPerSecond: rangeRateMetersPerSecond, rxCorrectedHz: rx, txCorrectedHz: tx)
    }

    static func estimateRangeRateMetersPerSecond(
        observer: CLLocation,
        positions: [N2YOSatPosition]
    ) -> Double? {
        guard positions.count >= 2 else { return nil }

        // Use the first two samples (1 second apart in N2YO output).
        let a = positions[0]
        let b = positions[1]

        let t0 = Double(a.timestamp)
        let t1 = Double(b.timestamp)
        let dt = t1 - t0
        guard dt > 0 else { return nil }

        let r0 = slantRangeMeters(observer: observer, sat: a)
        let r1 = slantRangeMeters(observer: observer, sat: b)
        return (r1 - r0) / dt
    }

    static func slantRangeMeters(observer: CLLocation, sat: N2YOSatPosition) -> Double {
        let obs = ecefMeters(latDeg: observer.coordinate.latitude, lonDeg: observer.coordinate.longitude, altMeters: observer.altitude)
        let satEcef = ecefMeters(latDeg: sat.satlatitude, lonDeg: sat.satlongitude, altMeters: sat.sataltitude * 1000.0)
        let dx = satEcef.x - obs.x
        let dy = satEcef.y - obs.y
        let dz = satEcef.z - obs.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    // WGS84 geodetic -> ECEF.
    private static func ecefMeters(latDeg: Double, lonDeg: Double, altMeters: Double) -> (x: Double, y: Double, z: Double) {
        let a = 6_378_137.0
        let f = 1.0 / 298.257_223_563
        let e2 = f * (2.0 - f)

        let lat = latDeg * .pi / 180.0
        let lon = lonDeg * .pi / 180.0

        let sinLat = sin(lat)
        let cosLat = cos(lat)
        let sinLon = sin(lon)
        let cosLon = cos(lon)

        let n = a / (1.0 - e2 * sinLat * sinLat).squareRoot()
        let x = (n + altMeters) * cosLat * cosLon
        let y = (n + altMeters) * cosLat * sinLon
        let z = (n * (1.0 - e2) + altMeters) * sinLat
        return (x, y, z)
    }
}
