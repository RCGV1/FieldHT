import Foundation

/// APRS-IS's non-secret login passcode derived from an amateur callsign.
public enum APRSISPasscode {
    public static func value(for callsign: String) -> String {
        let baseCallsign = callsign
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? ""
        let characters = Array(baseCallsign.uppercased().prefix(10).utf8)
        var hash = 29_666

        for index in stride(from: 0, to: characters.count, by: 2) {
            hash ^= Int(characters[index]) << 8
            if index + 1 < characters.count {
                hash ^= Int(characters[index + 1])
            }
        }

        return String(hash & 0x7FFF)
    }
}
