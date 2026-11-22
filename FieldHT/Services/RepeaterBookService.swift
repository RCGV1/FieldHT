//
//  RepeaterBookService.swift
//

import Foundation

public struct RepeaterBookResponse: Codable {
    public let count: Int
    public let results: [RepeaterResult]

    enum CodingKeys: String, CodingKey {
        case count
        case results
    }

    public init(count: Int, results: [RepeaterResult]) {
        self.count = count
        self.results = results
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intCount = try? container.decode(Int.self, forKey: .count) {
            count = intCount
        } else if let stringCount = try? container.decode(String.self, forKey: .count),
                  let intCount = Int(stringCount.trimmingCharacters(in: .whitespacesAndNewlines)) {
            count = intCount
        } else {
            count = 0
        }
        results = try container.decodeIfPresent([RepeaterResult].self, forKey: .results) ?? []
    }
}

public struct RepeaterResult: Codable, Sendable {
    public let frequency: String
    public let inputFreq: String
    public let pl: String
    public let callsign: String?

    enum CodingKeys: String, CodingKey {
        case frequency = "Frequency"
        case inputFreq = "Input Freq"
        case pl = "PL"
        case callsign = "Callsign"
    }
    
    /// Convert frequency string to Double (MHz)
    public var frequencyMHz: Double? {
        // Handle formats like "146.520" or "146.520000"
        return Double(frequency.trimmingCharacters(in: .whitespaces))
    }
    
    /// Convert input frequency string to Double (MHz)
    public var inputFreqMHz: Double? {
        return Double(inputFreq.trimmingCharacters(in: .whitespaces))
    }
    
    /// Convert PL (CTCSS tone) string to SubAudio
    public var subAudio: SubAudio? {
        guard let plValue = Double(pl.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        // PL values are typically CTCSS frequencies in Hz
        return .frequency(plValue)
    }
}

public final class RepeaterBookService {
    public static let apiTokenDefaultsKey = "com.fieldHT.repeaterBookAPIToken"

    public static let defaultBaseURL = URL(string: "https://www.repeaterbook.com/api/export.php")!
    public static let defaultROWBaseURL = URL(string: "https://www.repeaterbook.com/api/exportROW.php")!

    private let session: URLSession
    private let baseURL: URL
    private let rowBaseURL: URL
    private let userAgent: String
    private let tokenProvider: () -> String?

    public init(
        session: URLSession = .shared,
        baseURL: URL = RepeaterBookService.defaultBaseURL,
        rowBaseURL: URL = RepeaterBookService.defaultROWBaseURL,
        userAgent: String = "FieldHT/1.31 (+https://fieldht.app; contact@fieldht.app)",
        tokenProvider: @escaping () -> String? = {
            UserDefaults.standard.string(forKey: RepeaterBookService.apiTokenDefaultsKey)
        }
    ) {
        self.session = session
        self.baseURL = baseURL
        self.rowBaseURL = rowBaseURL
        self.userAgent = userAgent
        self.tokenProvider = tokenProvider
    }

    public func searchRepeaters(
        country: String,
        state: String?,
        city: String?
    ) async throws -> [RepeaterResult] {

        var components = URLComponents(url: endpointURL(for: country), resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "city", value: city)
        ]

        if isNorthAmerican(country) {
            queryItems.append(URLQueryItem(name: "state_id", value: state))
        } else {
            queryItems.append(URLQueryItem(name: "country", value: country))
        }

        components.queryItems = queryItems.filter { $0.value?.isEmpty == false }

        guard let url = components.url else {
            throw RepeaterBookError.invalidURL
        }
        
        print("RepeaterBookService: GET \(url)")
        return try await fetch(url: url).results
    }
    
    /// Search for a repeater by callsign
    /// - Parameter callsign: The callsign to search for (e.g., "W1AW")
    /// - Returns: Array of matching repeater results
    public func searchByCallsign(_ callsign: String) async throws -> [RepeaterResult] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "callsign", value: callsign.uppercased().trimmingCharacters(in: .whitespaces))
        ]

        guard let url = components.url else {
            throw RepeaterBookError.invalidURL
        }
        
        print("RepeaterBookService: Searching by callsign \(callsign) - GET \(url)")
        return try await fetch(url: url).results
    }

    private func fetch(url: URL) async throws -> RepeaterBookResponse {
        let request = try makeRequest(url: url)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RepeaterBookError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw decodeAPIError(statusCode: httpResponse.statusCode, data: data)
        }

        return try JSONDecoder().decode(RepeaterBookResponse.self, from: data)
    }

    private func makeRequest(url: URL) throws -> URLRequest {
        guard let token = normalizedToken else {
            throw RepeaterBookError.missingAPIToken
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(token, forHTTPHeaderField: "X-RB-App-Token")
        return request
    }

    private var normalizedToken: String? {
        let token = tokenProvider()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return token.isEmpty ? nil : token
    }

    private func endpointURL(for country: String) -> URL {
        isNorthAmerican(country) ? baseURL : rowBaseURL
    }

    private func isNorthAmerican(_ country: String) -> Bool {
        let normalized = country.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ||
            normalized == "us" ||
            normalized == "usa" ||
            normalized == "united states" ||
            normalized == "united states of america" ||
            normalized == "ca" ||
            normalized == "canada"
    }

    private func decodeAPIError(statusCode: Int, data: Data) -> RepeaterBookError {
        if let apiError = try? JSONDecoder().decode(RepeaterBookAPIError.self, from: data),
           let message = apiError.message {
            return .apiError(statusCode: statusCode, errorCode: apiError.errorCode, message: message)
        }

        let message = String(data: data, encoding: .utf8) ?? "Unknown RepeaterBook API error"
        return .apiError(statusCode: statusCode, errorCode: nil, message: message)
    }
}

private struct RepeaterBookAPIError: Decodable {
    let ok: Bool?
    let errorCode: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case errorCode = "error_code"
        case message
    }
}

public enum RepeaterBookError: Error, Equatable, LocalizedError {
    case missingAPIToken
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, errorCode: String?, message: String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIToken:
            return "RepeaterBook now requires an app-bound API token. Add your RepeaterBook API token in Settings."
        case .invalidURL:
            return "The RepeaterBook request URL could not be built."
        case .invalidResponse:
            return "RepeaterBook returned an invalid response."
        case .apiError(let statusCode, let errorCode, let message):
            if let errorCode {
                return "RepeaterBook API error \(statusCode) (\(errorCode)): \(message)"
            }
            return "RepeaterBook API error \(statusCode): \(message)"
        }
    }
}
