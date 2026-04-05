import Foundation

enum SatNogDBError: Error, LocalizedError {
    case invalidURL
    case httpStatus(Int)
    case decoding(Error, bodySnippet: String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid SatNOGS DB URL"
        case .httpStatus(let code):
            return "SatNOGS DB HTTP status \(code)"
        case .decoding(let error, let snippet):
            if let snippet, !snippet.isEmpty {
                return "Failed to decode SatNOGS DB response: \(error.localizedDescription)\n\(snippet)"
            }
            return "Failed to decode SatNOGS DB response: \(error.localizedDescription)"
        }
    }
}

final class SatNogDBClient {
    private let baseURL = URL(string: "https://db.satnogs.org/api/")!
    private let urlSession: URLSession

    private static let allSatellitesTTLSeconds: TimeInterval = 24 * 60 * 60
    private static let metadataTTLSeconds: TimeInterval = 7 * 24 * 60 * 60
    private static let transmittersTTLSeconds: TimeInterval = 7 * 24 * 60 * 60

    private struct CachedValue<Value: Codable>: Codable {
        let fetchedAtUnix: TimeInterval
        let value: Value
    }

    private static let allSatellitesCacheURL: URL = {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("satnogs_satellites.json", isDirectory: false)
    }()

    private static let satnogsCacheDirectoryURL: URL = {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("satnogs", isDirectory: true)
    }()

    private actor AllSatellitesCache {
        var sats: [SatNogSatellite]?
        var fetchedAt: Date?
        var task: Task<[SatNogSatellite], Error>?

        func freshSats(ttl: TimeInterval, now: Date = Date()) -> [SatNogSatellite]? {
            guard let sats, let fetchedAt else { return nil }
            guard now.timeIntervalSince(fetchedAt) < ttl else { return nil }
            return sats
        }

        func setTask(_ task: Task<[SatNogSatellite], Error>) {
            self.task = task
        }

        func store(_ sats: [SatNogSatellite], now: Date = Date()) {
            self.sats = sats
            self.fetchedAt = now
            self.task = nil
        }

        func clearTask() {
            self.task = nil
        }
    }

    private let allSatellitesCache = AllSatellitesCache()

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func allSatellites() async throws -> [SatNogSatellite] {
        // /satellites/?format=json
        // SatNOGS DB filtering parameters (search/name__icontains/etc) appear unreliable in practice;
        // we cache the full list and do client-side filtering for fast, relevant results.

        // Fast path: fresh cache / single-flight task.
        if let cached = await allSatellitesCache.freshSats(ttl: Self.allSatellitesTTLSeconds) {
            return cached
        }

        // Disk cache (best-effort) so the search index is instant after first fetch.
        if let disk = try? Self.loadAllSatellitesFromDisk(ttl: Self.allSatellitesTTLSeconds) {
            await allSatellitesCache.store(disk)
            return disk
        }

        if let task = await allSatellitesCache.task {
            return try await task.value
        }

        let task = Task<[SatNogSatellite], Error> { [baseURL, urlSession] in
            guard var components = URLComponents(url: baseURL.appendingPathComponent("satellites/"), resolvingAgainstBaseURL: false) else {
                throw SatNogDBError.invalidURL
            }
            components.queryItems = [
                URLQueryItem(name: "format", value: "json")
            ]
            guard let url = components.url else { throw SatNogDBError.invalidURL }

            do {
                let (data, response) = try await urlSession.data(from: url)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw SatNogDBError.httpStatus(http.statusCode)
                }
                do {
                    return try JSONDecoder().decode([SatNogSatellite].self, from: data)
                } catch {
                    let snippet = String(data: data.prefix(400), encoding: .utf8)
                    throw SatNogDBError.decoding(error, bodySnippet: snippet)
                }
            } catch {
                if let stale = try? Self.loadCachedValue(from: Self.allSatellitesCacheURL, ttl: nil) as [SatNogSatellite]? {
                    return stale
                }
                throw error
            }
        }

        await allSatellitesCache.setTask(task)

        do {
            let sats = try await task.value
            await allSatellitesCache.store(sats)
            Self.saveAllSatellitesToDisk(sats)
            return sats
        } catch {
            await allSatellitesCache.clearTask()
            throw error
        }
    }

    private static func loadAllSatellitesFromDisk(ttl: TimeInterval, now: Date = Date()) throws -> [SatNogSatellite]? {
        try loadCachedValue(from: allSatellitesCacheURL, ttl: ttl, now: now)
    }

    private static func saveAllSatellitesToDisk(_ sats: [SatNogSatellite]) {
        saveCachedValue(sats, to: allSatellitesCacheURL)
    }

    func satellitesByNorad(_ noradId: Int) async throws -> [SatNogSatellite] {
        // /satellites/?norad_cat_id=<NORAD>&format=json
        guard var components = URLComponents(url: baseURL.appendingPathComponent("satellites/"), resolvingAgainstBaseURL: false) else {
            throw SatNogDBError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "norad_cat_id", value: String(noradId)),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else { throw SatNogDBError.invalidURL }
        return try await cachedGet(
            url: url,
            cacheURL: Self.satellitesByNoradCacheURL(noradId: noradId),
            ttl: Self.metadataTTLSeconds
        )
    }

    func transmitters(noradId: Int) async throws -> [SatNogTransmitter] {
        // Prefer looking up sat_id first, then fetching by sat_id.
        // The transmitters endpoint can otherwise return an unexpectedly large unfiltered list.
        let noradCacheURL = Self.transmittersByNoradCacheURL(noradId: noradId)

        do {
            let sats = try await satellitesByNorad(noradId)
            if let satId = sats.first?.satId {
                let transmitters = try await transmitters(satId: satId)
                Self.saveCachedValue(transmitters, to: noradCacheURL)
                return transmitters
            }
        } catch {
            if let cached = try? Self.loadCachedValue(from: noradCacheURL, ttl: nil) as [SatNogTransmitter]? {
                return cached
            }
        }

        // Fallback to the norad_cat_id filter.
        guard var components = URLComponents(url: baseURL.appendingPathComponent("transmitters/"), resolvingAgainstBaseURL: false) else {
            throw SatNogDBError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "norad_cat_id", value: String(noradId)),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else { throw SatNogDBError.invalidURL }
        return try await cachedGet(
            url: url,
            cacheURL: noradCacheURL,
            ttl: Self.transmittersTTLSeconds
        )
    }

    func transmitters(satId: String) async throws -> [SatNogTransmitter] {
        // /transmitters/?sat_id=<sat_id>&format=json
        guard var components = URLComponents(url: baseURL.appendingPathComponent("transmitters/"), resolvingAgainstBaseURL: false) else {
            throw SatNogDBError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "sat_id", value: satId),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else { throw SatNogDBError.invalidURL }
        return try await cachedGet(
            url: url,
            cacheURL: Self.transmittersBySatIdCacheURL(satId: satId),
            ttl: Self.transmittersTTLSeconds
        )
    }

    func satellites(search: String, limit: Int = 25) async throws -> [SatNogSatellite] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let q = trimmed.lowercased()
        let all = try await allSatellites()

        // Filter client-side: by NORAD id, name, or alternate names.
        var out: [SatNogSatellite] = []
        out.reserveCapacity(min(limit, 50))
        for s in all {
            if Task.isCancelled { break }
            let norad = s.noradCatId
            let name = (s.name ?? "").lowercased()
            let names = (s.names ?? "").lowercased()

            if let norad, String(norad).contains(q) {
                out.append(s)
            } else if name.contains(q) {
                out.append(s)
            } else if !names.isEmpty, names.contains(q) {
                out.append(s)
            } else {
                continue
            }

            // Don't let this grow without bound; VM will re-rank.
            if out.count >= max(limit * 6, 150) {
                break
            }
        }

        if out.count <= limit { return out }
        return Array(out.prefix(limit))
    }

    private func get<T: Decodable>(url: URL) async throws -> T {
        let (data, response) = try await urlSession.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw SatNogDBError.httpStatus(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let snippet = String(data: data.prefix(400), encoding: .utf8)
            throw SatNogDBError.decoding(error, bodySnippet: snippet)
        }
    }

    private func cachedGet<T: Codable>(url: URL, cacheURL: URL, ttl: TimeInterval, now: Date = Date()) async throws -> T {
        if let fresh = try? Self.loadCachedValue(from: cacheURL, ttl: ttl, now: now) as T? {
            return fresh
        }

        do {
            let value: T = try await get(url: url)
            Self.saveCachedValue(value, to: cacheURL, now: now)
            return value
        } catch {
            if let stale = try? Self.loadCachedValue(from: cacheURL, ttl: nil, now: now) as T? {
                return stale
            }
            throw error
        }
    }

    private static func satellitesByNoradCacheURL(noradId: Int) -> URL {
        cacheFileURL(named: "satellite_norad_\(noradId).json")
    }

    private static func transmittersByNoradCacheURL(noradId: Int) -> URL {
        cacheFileURL(named: "transmitters_norad_\(noradId).json")
    }

    private static func transmittersBySatIdCacheURL(satId: String) -> URL {
        cacheFileURL(named: "transmitters_satid_\(sanitizedCacheComponent(satId)).json")
    }

    private static func cacheFileURL(named name: String) -> URL {
        ensureCacheDirectory()
        return satnogsCacheDirectoryURL.appendingPathComponent(name, isDirectory: false)
    }

    private static func ensureCacheDirectory() {
        try? FileManager.default.createDirectory(
            at: satnogsCacheDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private static func sanitizedCacheComponent(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"[^A-Za-z0-9._-]"#,
            with: "_",
            options: .regularExpression
        )
    }

    private static func loadCachedValue<Value: Codable>(
        from url: URL,
        ttl: TimeInterval?,
        now: Date = Date()
    ) throws -> Value? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()

        if let envelope = try? decoder.decode(CachedValue<Value>.self, from: data) {
            if let ttl, now.timeIntervalSince1970 - envelope.fetchedAtUnix > ttl {
                return nil
            }
            return envelope.value
        }

        let rawValue = try decoder.decode(Value.self, from: data)
        if let ttl {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values.contentModificationDate, now.timeIntervalSince(modified) > ttl {
                return nil
            }
        }
        return rawValue
    }

    private static func saveCachedValue<Value: Codable>(_ value: Value, to url: URL, now: Date = Date()) {
        do {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try JSONEncoder().encode(CachedValue(fetchedAtUnix: now.timeIntervalSince1970, value: value))
            try data.write(to: url, options: [.atomic])
        } catch {
            // Best-effort only.
        }
    }
}
