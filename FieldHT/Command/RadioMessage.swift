import Foundation

/// Radio message type (union of all possible messages)
public enum RadioMessage {
    case reply(ReplyMessage)
    case event(EventMessage)
}

/// Reply message types
public enum ReplyMessage {
    case deviceInfo(DeviceInfo)
    case channel(Channel)
    case settings(Settings)
    case status(Status)
    case position(Position)
    case batteryVoltage(Double)
    case batteryLevel(Int)
    case batteryLevelAsPercentage(Int)
    case beaconSettings(BeaconSettings)
    case regionName(String)
    case success
    case error(ReplyStatus, String)
}

