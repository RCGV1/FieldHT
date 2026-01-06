#!/usr/bin/env swift

import Foundation

// Simple test script for RepeaterBook API
// Usage: swift test_repeaterbook_api.swift <callsign>

struct RepeaterBookResponse: Codable {
    let count: Int
    let results: [RepeaterResult]
}

struct RepeaterResult: Codable {
    let frequency: String
    let inputFreq: String
    let pl: String
    let callsign: String?

    enum CodingKeys: String, CodingKey {
        case frequency = "Frequency"
        case inputFreq = "Input Freq"
        case pl = "PL"
        case callsign = "Callsign"
    }
}

func testRepeaterBookAPI(callsign: String) async throws {
    let baseURL = "https://www.repeaterbook.com/api/export.php"
    var components = URLComponents(string: baseURL)!
    components.queryItems = [
        URLQueryItem(name: "callsign", value: callsign.uppercased().trimmingCharacters(in: .whitespaces))
    ]

    guard let url = components.url else {
        throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
    }

    print("Testing RepeaterBook API...")
    print("URL: \(url)")
    print("Searching for callsign: \(callsign.uppercased())")
    print()

    var request = URLRequest(url: url)
    // RepeaterBook API requires User-Agent with program name and email
    request.setValue("FieldHT-Test/1.0 (test@fieldht.app)", forHTTPHeaderField: "User-Agent")
    
    let (data, response) = try await URLSession.shared.data(for: request)
    
    guard let httpResponse = response as? HTTPURLResponse else {
        throw NSError(domain: "TestError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
    }
    
    print("HTTP Status: \(httpResponse.statusCode)")
    print()
    
    if httpResponse.statusCode != 200 {
        if let errorString = String(data: data, encoding: .utf8) {
            print("Error response: \(errorString)")
        }
        return
    }
    
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(RepeaterBookResponse.self, from: data)
    
    print("Found \(decoded.count) repeater(s)")
    print()
    
    for (index, result) in decoded.results.enumerated() {
        print("Repeater \(index + 1):")
        print("  Callsign: \(result.callsign ?? "N/A")")
        print("  Frequency (RX): \(result.frequency) MHz")
        print("  Input Frequency (TX): \(result.inputFreq) MHz")
        print("  PL (CTCSS): \(result.pl) Hz")
        print()
    }
    
    if decoded.results.isEmpty {
        print("No repeaters found for callsign: \(callsign)")
    }
}

// Main execution
let arguments = CommandLine.arguments

if arguments.count < 2 {
    print("Usage: swift test_repeaterbook_api.swift <callsign>")
    print("Example: swift test_repeaterbook_api.swift W1AW")
    exit(1)
}

let callsign = arguments[1]

Task {
    do {
        try await testRepeaterBookAPI(callsign: callsign)
        print("✅ Test completed successfully")
    } catch {
        print("❌ Test failed: \(error.localizedDescription)")
        exit(1)
    }
    exit(0)
}

// Keep the script running
RunLoop.main.run()
