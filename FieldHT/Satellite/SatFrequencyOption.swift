import Foundation

struct SatFrequencyOption: Identifiable, Hashable {
    let id: String
    let title: String
    let rxMHz: Double?
    let txMHz: Double?
    let rxCTCSSHz: Double?
    let txCTCSSHz: Double?
    let isCustom: Bool
}
