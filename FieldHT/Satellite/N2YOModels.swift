import Foundation

// MARK: - Shared

struct N2YOInfo: Decodable {
    let satname: String?
    let satid: Int?
    let transactionscount: Int?

    // above endpoint
    let category: String?
    let satcount: Int?
    let passescount: Int?
}

// MARK: - Above (What's up?)

struct N2YOAboveResponse: Decodable {
    let info: N2YOInfo
    let above: [N2YOAboveSatellite]
}

struct N2YOAboveSatellite: Decodable, Identifiable {
    var id: Int { satid }

    let satid: Int
    let satname: String
    let intDesignator: String?
    let launchDate: String?
    let satlat: Double
    let satlng: Double
    let satalt: Double
}

// MARK: - Positions

struct N2YOPositionsResponse: Decodable {
    let info: N2YOInfo
    let positions: [N2YOSatPosition]
}

struct N2YOSatPosition: Decodable, Equatable {
    let satlatitude: Double
    let satlongitude: Double
    let sataltitude: Double
    let azimuth: Double
    let elevation: Double
    let ra: Double?
    let dec: Double?
    let timestamp: Int
}

// MARK: - Radio passes

struct N2YORadioPassesResponse: Decodable {
    let info: N2YOInfo
    let passes: [N2YORadioPass]
}

struct N2YORadioPass: Decodable {
    let startAz: Double
    let startAzCompass: String?
    let startUTC: Int

    let maxAz: Double
    let maxAzCompass: String?
    let maxEl: Double
    let maxUTC: Int

    let endAz: Double
    let endAzCompass: String?
    let endUTC: Int
}
