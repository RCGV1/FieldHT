import Foundation

struct RadioChoice: Identifiable, Equatable {
    let value: Int
    let label: String

    var id: Int { value }
}

enum RadioPresentation {
    static let screenTimeoutOptions: [RadioChoice] = [
        RadioChoice(value: 5, label: "5 seconds"),
        RadioChoice(value: 10, label: "10 seconds"),
        RadioChoice(value: 15, label: "15 seconds"),
        RadioChoice(value: 20, label: "20 seconds"),
        RadioChoice(value: 25, label: "25 seconds"),
        RadioChoice(value: 30, label: "30 seconds"),
        RadioChoice(value: 31, label: "Always On")
    ]

    static let txHoldOptions: [RadioChoice] = (0...15).map { value in
        RadioChoice(value: value, label: "\(value) seconds")
    }

    static let txLimitOptions: [RadioChoice] = [
        RadioChoice(value: 0, label: "Off")
    ] + (1...30).map { value in
        RadioChoice(value: value, label: "\(value * 10) seconds")
    }

    static func sMeterLabel(forPercent value: Int) -> String {
        let clamped = min(max(value, 0), 100)
        if clamped >= 96 {
            return "S9+"
        }
        return "S\(min(9, max(0, clamped / 10)))"
    }

    static func speakerMicName(model: String?, isBS22: Bool) -> String {
        let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedModel.isEmpty {
            return trimmedModel
        }
        return isBS22 ? "BS-22 Speaker Mic" : "Speaker Mic"
    }
}
