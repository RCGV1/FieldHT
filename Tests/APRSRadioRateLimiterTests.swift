import Foundation

@main
enum APRSRadioRateLimiterTests {
    static func main() {
        var failures = 0

        func expect(_ condition: Bool, _ message: String) {
            guard condition else {
                failures += 1
                fputs("FAIL: \(message)\n", stderr)
                return
            }
        }

        let start = Date(timeIntervalSinceReferenceDate: 0)

        var safeLimiter = APRSRadioRateLimiter.safeDefault
        expect(safeLimiter.minimumInterval == 30, "the default RF interval must prevent a rapid APRS burst")
        expect(safeLimiter.maximumPacketsPerMinute == 2, "the default RF cap must remain conservative")
        expect(safeLimiter.allowsSend(at: start), "the first APRS packet is allowed")
        expect(!safeLimiter.allowsSend(at: start.addingTimeInterval(29)), "the default holds packets for thirty seconds")
        expect(safeLimiter.allowsSend(at: start.addingTimeInterval(30)), "a second packet may be sent after the quiet interval")
        expect(!safeLimiter.allowsSend(at: start.addingTimeInterval(45)), "the default prevents another packet before the quiet interval expires")

        var limiter = APRSRadioRateLimiter(minimumInterval: 5, maximumPacketsPerMinute: 2)
        expect(limiter.allowsSend(at: start), "first APRS packet is allowed")
        expect(!limiter.allowsSend(at: start.addingTimeInterval(4)), "packets inside the RF spacing window are held")
        expect(limiter.allowsSend(at: start.addingTimeInterval(5)), "packet after the spacing window is allowed")
        expect(!limiter.allowsSend(at: start.addingTimeInterval(10)), "per-minute cap prevents APRS burst forwarding")
        expect(limiter.allowsSend(at: start.addingTimeInterval(61)), "rate limit recovers after one minute")

        if failures > 0 {
            exit(1)
        }

        print("APRSRadioRateLimiterTests passed")
    }
}
