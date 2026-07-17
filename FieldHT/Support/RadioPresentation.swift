import Foundation

struct RadioChoice: Identifiable, Equatable {
    let value: Int
    let label: String

    var id: Int { value }
}

enum RadioPresentation {
    static let screenTimeoutOptions: [RadioChoice] = [
        RadioChoice(value: 0, label: "Never"),
        RadioChoice(value: 1, label: "3 seconds"),
        RadioChoice(value: 2, label: "4 seconds"),
        RadioChoice(value: 3, label: "5 seconds"),
        RadioChoice(value: 4, label: "6 seconds"),
        RadioChoice(value: 5, label: "7 seconds"),
        RadioChoice(value: 6, label: "8 seconds"),
        RadioChoice(value: 7, label: "9 seconds"),
        RadioChoice(value: 8, label: "10 seconds"),
        RadioChoice(value: 9, label: "15 seconds"),
        RadioChoice(value: 10, label: "20 seconds"),
        RadioChoice(value: 11, label: "30 seconds"),
        RadioChoice(value: 12, label: "1 minute"),
        RadioChoice(value: 13, label: "90 seconds"),
        RadioChoice(value: 14, label: "2 minutes"),
        RadioChoice(value: 15, label: "3 minutes"),
        RadioChoice(value: 16, label: "4 minutes"),
        RadioChoice(value: 17, label: "5 minutes")
    ]

    static let txHoldOptions: [RadioChoice] = [
        RadioChoice(value: 0, label: "Off")
    ] + (1...10).map { value in
        RadioChoice(value: value, label: String(format: "%.1f seconds", Double(value) / 10))
    }

    static let txLimitOptions: [RadioChoice] = [
        RadioChoice(value: 0, label: "Off")
    ] + (1...30).map { value in
        RadioChoice(value: value, label: "\(value * 10) seconds")
    }

    static let micGainOptions: [RadioChoice] = (0...7).map { value in
        let decibels = (value - 3) * 3
        let label = decibels > 0 ? "+\(decibels) dB" : "\(decibels) dB"
        return RadioChoice(value: value, label: label)
    }

    static let alarmVolumeOptions: [RadioChoice] = [RadioChoice(value: 0, label: "Mute")] + (1...15).map { value in
        RadioChoice(value: value, label: "Level \(value)")
    }

    static func sMeterLabel(forPercent value: Int) -> String {
        let clamped = min(max(value, 0), 100)
        if clamped >= 96 {
            return "S9+"
        }
        return "S\(min(9, max(0, clamped / 10)))"
    }

    static func channelMenuLabel(channelID: Int, name: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? "Unnamed channel" : trimmedName
        return "\(channelID + 1). \(displayName)"
    }

    static func speakerMicName(model: String?, isBS22: Bool) -> String {
        let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedModel.isEmpty {
            return trimmedModel
        }
        return isBS22 ? "BS-22 Speaker Mic" : "Speaker Mic"
    }
}
