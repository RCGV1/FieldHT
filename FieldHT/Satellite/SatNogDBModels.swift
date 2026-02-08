import Foundation

// Minimal SatNOGS DB models used for frequency selection.
// Public API docs: https://db.satnogs.org/api/

struct SatNogSatellite: Codable, Identifiable, Hashable {
    let satId: String
    let noradCatId: Int?
    let name: String?
    let names: String?
    let image: String?
    let status: String?
    let launched: String?
    let website: String?
    let operatorName: String?
    let countries: String?

    var id: String { satId }

    enum CodingKeys: String, CodingKey {
        case satId = "sat_id"
        case noradCatId = "norad_cat_id"
        case name
        case names
        case image
        case status
        case launched
        case website
        case operatorName = "operator"
        case countries
    }
}

struct SatNogTransmitter: Codable, Identifiable, Hashable {
    let uuid: String
    let description: String?
    let alive: Bool?
    let type: String?
    let mode: String?
    let uplinkMode: String?
    let invert: Bool?
    let baud: Double?
    let status: String?
    let unconfirmed: Bool?
    let frequencyViolation: Bool?
    let noradCatId: Int?

    // Values are in Hz when present.
    let downlinkLow: Double?
    let downlinkHigh: Double?
    let downlinkDrift: Double?
    let uplinkLow: Double?
    let uplinkHigh: Double?

    var id: String { uuid }

    enum CodingKeys: String, CodingKey {
        case uuid
        case description
        case alive
        case type
        case mode
        case uplinkMode = "uplink_mode"
        case invert
        case baud
        case status
        case unconfirmed
        case frequencyViolation = "frequency_violation"
        case noradCatId = "norad_cat_id"
        case downlinkLow = "downlink_low"
        case downlinkHigh = "downlink_high"
        case downlinkDrift = "downlink_drift"
        case uplinkLow = "uplink_low"
        case uplinkHigh = "uplink_high"
    }
}
