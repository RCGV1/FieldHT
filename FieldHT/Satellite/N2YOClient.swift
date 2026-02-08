import Foundation

enum N2YOClientError: Error, LocalizedError {
    case missingAPIKey
    case invalidURL
    case httpStatus(Int)
    case emptyBody(Int)
    case decoding(Error, bodySnippet: String?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing N2YO API key. Add it in-app (Satellite view) or via Xcode scheme env var for debug."
        case .invalidURL:
            return "Invalid N2YO URL"
        case .httpStatus(let code):
            return "N2YO HTTP status \(code)"
        case .emptyBody(let code):
            return "N2YO returned an empty response (HTTP \(code)). Check API key / rate limit."
        case .decoding(let error, let snippet):
            if let snippet, !snippet.isEmpty {
                return "Failed to decode N2YO response: \(error.localizedDescription)\n\(snippet)"
            }
            return "Failed to decode N2YO response: \(error.localizedDescription)"
        }
    }
}

final class N2YOClient {
    private let baseURL = URL(string: "https://api.n2yo.com/rest/v1/satellite/")!
    private let urlSession: URLSession
    private let posixLocale = Locale(identifier: "en_US_POSIX")

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func above(observerLat: Double, observerLng: Double, observerAltMeters: Double, searchRadiusDeg: Int = 90, categoryId: Int = 18) async throws -> N2YOAboveResponse {
        // /above/{observer_lat}/{observer_lng}/{observer_alt}/{search_radius}/{category_id}
        let lat = String(format: "%.6f", locale: posixLocale, observerLat)
        let lng = String(format: "%.6f", locale: posixLocale, observerLng)
        let alt = Int(Swift.max(0.0, observerAltMeters).rounded())
        let path = "above/\(lat)/\(lng)/\(alt)/\(searchRadiusDeg)/\(categoryId)/"
        return try await get(path: path)
    }

    func positions(satId: Int, observerLat: Double, observerLng: Double, observerAltMeters: Double, seconds: Int = 60) async throws -> N2YOPositionsResponse {
        let clamped = max(1, min(300, seconds))
        // /positions/{id}/{observer_lat}/{observer_lng}/{observer_alt}/{seconds}
        let lat = String(format: "%.6f", locale: posixLocale, observerLat)
        let lng = String(format: "%.6f", locale: posixLocale, observerLng)
        let alt = Int(Swift.max(0.0, observerAltMeters).rounded())
        let path = "positions/\(satId)/\(lat)/\(lng)/\(alt)/\(clamped)/"
        return try await get(path: path)
    }

    func radioPasses(satId: Int, observerLat: Double, observerLng: Double, observerAltMeters: Double, days: Int = 1, minElevationDeg: Int = 10) async throws -> N2YORadioPassesResponse {
        let clampedDays = max(1, min(10, days))
        // /radiopasses/{id}/{observer_lat}/{observer_lng}/{observer_alt}/{days}/{min_elevation}
        let lat = String(format: "%.6f", locale: posixLocale, observerLat)
        let lng = String(format: "%.6f", locale: posixLocale, observerLng)
        let alt = Int(Swift.max(0.0, observerAltMeters).rounded())
        let path = "radiopasses/\(satId)/\(lat)/\(lng)/\(alt)/\(clampedDays)/\(minElevationDeg)/"
        return try await get(path: path)
    }

    private func get<T: Decodable>(path: String) async throws -> T {
        let apiKey = try Self.apiKey()

        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw N2YOClientError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "apiKey", value: apiKey)]

        guard let url = components.url else { throw N2YOClientError.invalidURL }

        let (data, response) = try await urlSession.data(from: url)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw N2YOClientError.httpStatus(http.statusCode)
        }
        if data.isEmpty {
            throw N2YOClientError.emptyBody(statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let snippet = String(data: data.prefix(400), encoding: .utf8)
            throw N2YOClientError.decoding(error, bodySnippet: snippet)
        }
    }

    private static func apiKey() throws -> String {
        // 1) Environment variable (easy for dev/simulator via Xcode scheme)
        if let env = ProcessInfo.processInfo.environment["N2YO_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !env.isEmpty {
            return env
        }

        // 2) Keychain/UserDefaults (in-app entry). UserDefaults value is migrated to Keychain.
        if let stored = N2YOAPIKeyStore.get() {
            return stored
        }

        // 3) Info.plist (avoid committing real keys)
        if let plist = (Bundle.main.object(forInfoDictionaryKey: "N2YO_API_KEY") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !plist.isEmpty {
            return plist
        }

        throw N2YOClientError.missingAPIKey
    }
}
