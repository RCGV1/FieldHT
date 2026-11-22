import Foundation

public enum ConnectionUXPolicy {
    public static let maximumAutomaticRadioAttempts = 3
    public static let scanDuration: TimeInterval = 15

    public static func shouldRetryRadio(afterFailedAttempts count: Int) -> Bool {
        count >= 0 && count < maximumAutomaticRadioAttempts
    }
}
