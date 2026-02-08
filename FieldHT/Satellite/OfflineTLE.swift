import Foundation
import CoreLocation

#if canImport(SatelliteKit)
import SatelliteKit
#endif

struct TLERecord: Codable, Equatable {
    let noradId: Int
    let name: String
    let line1: String
    let line2: String
    let fetchedAtUnix: Double
}

enum TLEClientError: Error, LocalizedError {
    case invalidURL
    case httpStatus(Int)
    case emptyBody
    case parseFailed
    case sgp4Unavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid TLE URL"
        case .httpStatus(let code):
            return "TLE HTTP status \(code)"
        case .emptyBody:
            return "TLE endpoint returned an empty body"
        case .parseFailed:
            return "Failed to parse TLE response"
        case .sgp4Unavailable:
            return "Propagation unavailable (SatelliteKit not linked)"
        }
    }
}

final class TLEClient {
    private let urlSession: URLSession

    // This file is used from a non-MainActor context (TLEStore actor).
    // The project builds with `-default-isolation=MainActor`, so opt this type out explicitly.
    nonisolated init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    nonisolated func fetchTLE(noradId: Int, fallbackName: String? = nil) async throws -> TLERecord {
        // Celestrak GP (TLE) endpoint.
        // Example: https://celestrak.org/NORAD/elements/gp.php?CATNR=25544&FORMAT=TLE
        var components = URLComponents(string: "https://celestrak.org/NORAD/elements/gp.php")
        components?.queryItems = [
            URLQueryItem(name: "CATNR", value: String(noradId)),
            URLQueryItem(name: "FORMAT", value: "TLE")
        ]
        guard let url = components?.url else { throw TLEClientError.invalidURL }

        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15
        req.setValue("FieldHT/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await urlSession.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TLEClientError.httpStatus(http.statusCode)
        }
        guard !data.isEmpty else { throw TLEClientError.emptyBody }

        let text = String(decoding: data, as: UTF8.self)
        guard let parsed = Self.parseTLEText(text, fallbackName: fallbackName) else {
            throw TLEClientError.parseFailed
        }

        return TLERecord(
            noradId: noradId,
            name: parsed.name,
            line1: parsed.line1,
            line2: parsed.line2,
            fetchedAtUnix: Date().timeIntervalSince1970
        )
    }

    nonisolated static func parseTLEText(_ text: String, fallbackName: String?) -> (name: String, line1: String, line2: String)? {
        let lines = text
            .replacingOccurrences(of: "\r", with: "")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Expect either:
        // - [name, line1, line2]
        // - [line1, line2]
        if lines.count >= 3, lines[1].hasPrefix("1 "), lines[2].hasPrefix("2 ") {
            let name = Self.cleanTLEName(lines[0], fallback: fallbackName)
            return (name: name, line1: lines[1], line2: lines[2])
        }
        if lines.count >= 2, lines[0].hasPrefix("1 "), lines[1].hasPrefix("2 ") {
            let name = Self.cleanTLEName("", fallback: fallbackName)
            return (name: name, line1: lines[0], line2: lines[1])
        }
        return nil
    }

    nonisolated private static func cleanTLEName(_ raw: String, fallback: String?) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("0 ") {
            let dropped = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !dropped.isEmpty { return dropped }
        }
        if !trimmed.isEmpty { return trimmed }
        return (fallback?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? ""
    }
}

actor TLEStore {
    private struct Cache: Codable {
        var recordsByNoradId: [Int: TLERecord]
    }

    private static let userDefaultsKey = "com.fieldHT.sat.tleCache.v1"
    private static let ttlSeconds: Double = 24 * 3600

    private let client: TLEClient
    private var cache: Cache
    private var inFlight: [Int: Task<Void, Never>] = [:]

    init(client: TLEClient = TLEClient()) {
        self.client = client
        self.cache = Self.loadFromDefaultsBestEffort() ?? Cache(recordsByNoradId: [:])
    }

    func cachedRecord(noradId: Int) -> TLERecord? {
        cache.recordsByNoradId[noradId]
    }

    func cachedFreshRecord(noradId: Int, nowUnix: Double = Date().timeIntervalSince1970) -> TLERecord? {
        guard let rec = cache.recordsByNoradId[noradId] else { return nil }
        guard (nowUnix - rec.fetchedAtUnix) <= Self.ttlSeconds else { return nil }
        return rec
    }

    func ensureFresh(noradId: Int, fallbackName: String? = nil, nowUnix: Double = Date().timeIntervalSince1970) {
        if cachedFreshRecord(noradId: noradId, nowUnix: nowUnix) != nil { return }
        if inFlight[noradId] != nil { return }

        inFlight[noradId] = Task {
            await self.fetchAndStore(noradId: noradId, fallbackName: fallbackName)
        }
    }

    private func fetchAndStore(noradId: Int, fallbackName: String?) async {
        defer { inFlight[noradId] = nil }
        do {
            let rec = try await client.fetchTLE(noradId: noradId, fallbackName: fallbackName)
            store(rec)
        } catch {
            // Best-effort: keep whatever we already had.
        }
    }

    private func store(_ rec: TLERecord) {
        cache.recordsByNoradId[rec.noradId] = rec
        persistToDefaultsBestEffort()
    }

    private static func loadFromDefaultsBestEffort() -> Cache? {
        guard let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey) else { return nil }
        do {
            return try JSONDecoder().decode(Cache.self, from: data)
        } catch {
            return nil
        }
    }

    private func persistToDefaultsBestEffort() {
        do {
            let data = try JSONEncoder().encode(cache)
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        } catch {
            // Ignore.
        }
    }
}

struct OfflineSatPosition: Equatable {
    let latDeg: Double
    let lonDeg: Double
    let altKm: Double
    let azDeg: Double
    let elDeg: Double
    let timestamp: Int
}

enum OfflineTLEPropagator {
    static func positions(
        tle: TLERecord,
        observer: CLLocation,
        start: Date,
        seconds: Int
    ) throws -> [OfflineSatPosition] {
#if canImport(SatelliteKit)
        let obs = LatLonAlt(
            observer.coordinate.latitude,
            observer.coordinate.longitude,
            observer.altitude / 1000.0
        )

        let elements = try Elements(tle.name, tle.line1, tle.line2)
        let sat = Satellite(withTLE: elements)
        let baseMins = sat.minsAfterEpoch

        let clamped = max(1, min(300, seconds))
        var out: [OfflineSatPosition] = []
        out.reserveCapacity(clamped)

        for i in 0..<clamped {
            let t = start.addingTimeInterval(TimeInterval(i))
            let mins = baseMins + (Double(i) / 60.0)

            let geo = try sat.geoPosition(minsAfterEpoch: mins)
            let top = try sat.topPosition(minsAfterEpoch: mins, observer: obs)

            var lon = geo.lon
            if lon > 180.0 { lon -= 360.0 }

            out.append(OfflineSatPosition(
                latDeg: geo.lat,
                lonDeg: lon,
                altKm: geo.alt,
                azDeg: top.azim,
                elDeg: top.elev,
                timestamp: Int(t.timeIntervalSince1970)
            ))
        }

        return out
#else
        throw TLEClientError.sgp4Unavailable
#endif
    }

    static func positionsSampled(
        tle: TLERecord,
        observer: CLLocation,
        start: Date,
        seconds: Int,
        stepSeconds: Int
    ) throws -> [OfflineSatPosition] {
#if canImport(SatelliteKit)
        let obs = LatLonAlt(
            observer.coordinate.latitude,
            observer.coordinate.longitude,
            observer.altitude / 1000.0
        )

        let elements = try Elements(tle.name, tle.line1, tle.line2)
        let sat = Satellite(withTLE: elements)
        let baseMins = sat.minsAfterEpoch

        let clampedSeconds = max(1, min(6 * 3600, seconds))
        let step = max(1, min(60, stepSeconds))

        // Keep this bounded so map updates stay cheap.
        let maxPoints = 600
        let pointCount = min(maxPoints, (clampedSeconds / step) + 1)

        var out: [OfflineSatPosition] = []
        out.reserveCapacity(pointCount)

        for idx in 0..<pointCount {
            let i = idx * step
            let t = start.addingTimeInterval(TimeInterval(i))
            let mins = baseMins + (Double(i) / 60.0)

            let geo = try sat.geoPosition(minsAfterEpoch: mins)
            let top = try sat.topPosition(minsAfterEpoch: mins, observer: obs)

            var lon = geo.lon
            if lon > 180.0 { lon -= 360.0 }

            out.append(OfflineSatPosition(
                latDeg: geo.lat,
                lonDeg: lon,
                altKm: geo.alt,
                azDeg: top.azim,
                elDeg: top.elev,
                timestamp: Int(t.timeIntervalSince1970)
            ))
        }

        return out
#else
        throw TLEClientError.sgp4Unavailable
#endif
    }
}
