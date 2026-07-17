import Foundation

/// Limits APRS-IS traffic forwarded over RF. APRS-IS can deliver a large burst
/// after login; sending that burst straight to a handheld is both noisy and
/// likely to trigger the radio's transmit protections.
struct APRSRadioRateLimiter {
    static let safeDefault = APRSRadioRateLimiter(
        minimumInterval: 5,
        maximumPacketsPerMinute: 12
    )

    let minimumInterval: TimeInterval
    let maximumPacketsPerMinute: Int
    private var sentAt: [Date] = []

    init(minimumInterval: TimeInterval, maximumPacketsPerMinute: Int) {
        self.minimumInterval = minimumInterval
        self.maximumPacketsPerMinute = maximumPacketsPerMinute
    }

    mutating func allowsSend(at date: Date = Date()) -> Bool {
        sentAt.removeAll { date.timeIntervalSince($0) >= 60 }

        guard sentAt.count < maximumPacketsPerMinute else { return false }
        guard let lastSent = sentAt.last,
              date.timeIntervalSince(lastSent) < minimumInterval
        else {
            sentAt.append(date)
            return true
        }

        return false
    }
}
