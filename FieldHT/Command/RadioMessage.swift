import Foundation

/// Radio message type (union of all possible messages)
public enum RadioMessage {
    case reply(ReplyMessage)
    case event(EventMessage)
}

/// Operating modes carried by the UV-PRO frequency-mode command.
/// The public BTECH app uses the same command for scan and satellite features.
public enum FrequencyMode: Int, Sendable {
    case off = 0
    case scanUp = 1
    case scanDown = 2
    case exact = 3
    case satellite = 10
}

public enum FrequencyScanStep: Int, CaseIterable, Sendable {
    case fiveKHz = 0
    case sixPointTwoFiveKHz = 1
    case tenKHz = 2
    case twelvePointFiveKHz = 3
    case fifteenKHz = 4
    case twentyFiveKHz = 5

    public init(kHz: Double) {
        switch kHz {
        case 5: self = .fiveKHz
        case 6.25: self = .sixPointTwoFiveKHz
        case 10: self = .tenKHz
        case 12.5: self = .twelvePointFiveKHz
        case 15: self = .fifteenKHz
        default: self = .twentyFiveKHz
        }
    }
}

public struct FrequencyModeStatus: Sendable, Equatable {
    public let rxMHz: Double
    public let txMHz: Double
    public let step: FrequencyScanStep
    public let mode: FrequencyMode?
    public let isTuned: Bool
    public let isSeeking: Bool
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
    case rcBatteryLevel(Int)
    case beaconSettings(BeaconSettings)
    case aprsPath(String)
    case regionName(String)
    case pf(PFConfig)
    case pfActions(Data)
    case volume(Int)
    case frequencyModeStatus(FrequencyModeStatus)
    case registerNotificationAck(UInt8)
    case success
    case error(ReplyStatus, String)
}
