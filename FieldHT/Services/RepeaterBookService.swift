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

        guard let url = components.url else {
            throw NSError(domain: "RepeaterBookService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        print("RepeaterBookService: GET \(url)")

        var request = URLRequest(url: url)
        // RepeaterBook API requires User-Agent with program name and email
        request.setValue("FieldHT/1.0 (contact@fieldht.app)", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "RepeaterBookService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "RepeaterBookService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API error: \(errorMessage)"])
        }
        
        let decoded = try JSONDecoder().decode(RepeaterBookResponse.self, from: data)
        return decoded.results
    }
    
    /// Search for a repeater by callsign
    /// - Parameter callsign: The callsign to search for (e.g., "W1AW")
    /// - Returns: Array of matching repeater results
    public func searchByCallsign(_ callsign: String) async throws -> [RepeaterResult] {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "callsign", value: callsign.uppercased().trimmingCharacters(in: .whitespaces))
        ]

        guard let url = components.url else {
            throw NSError(domain: "RepeaterBookService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        print("RepeaterBookService: Searching by callsign \(callsign) - GET \(url)")

        var request = URLRequest(url: url)
        // RepeaterBook API requires User-Agent with program name and email
        request.setValue("FieldHT/1.0 (benjaminfaer@gmail.com)", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "RepeaterBookService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "RepeaterBookService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API error: \(errorMessage)"])
        }
        
        let decoded = try JSONDecoder().decode(RepeaterBookResponse.self, from: data)
        return decoded.results
    }
}
