//
//  RepeaterBookService.swift
//

import Foundation

public struct RepeaterBookResponse: Codable {
    public let count: Int
    public let results: [RepeaterResult]
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
}

public final class RepeaterBookService {

    private let baseURL = "https://www.repeaterbook.com/api/export.php"

    public init() {}

    public func searchRepeaters(
        country: String,
        state: String?,
        city: String?
    ) async throws -> [RepeaterResult] {

        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "city", value: city)
        ].filter { $0.value != nil }

        let url = components.url!
        print("RepeaterBookService: GET \(url)")

        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(RepeaterBookResponse.self, from: data)
        return decoded.results
    }
}
