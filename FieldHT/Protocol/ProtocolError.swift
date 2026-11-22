import Foundation

/// Shared by the BLE and Bluetooth Classic command transports.
public enum ProtocolError: LocalizedError {
    case notImplemented
    case decodeError(String)
    case invalidMessage
    case invalidReply
    case timeout
    case commandFailed(ReplyStatus, String)
    case invalidCommandGroup
    case invalidPowerStatusType

    public var errorDescription: String? {
        switch self {
        case .notImplemented: return "Protocol decoder not fully implemented"
        case .decodeError(let message): return "Failed to decode message: \(message)"
        case .invalidMessage: return "Invalid message format"
        case .invalidReply: return "Invalid reply format"
        case .timeout: return "Command timed out"
        case .commandFailed(let status, let message): return "Command failed: \(status) - \(message)"
        case .invalidCommandGroup: return "Invalid command group"
        case .invalidPowerStatusType: return "Invalid power status type"
        }
    }
}
