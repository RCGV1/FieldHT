import Foundation

/// Packet format
public enum PacketFormat: String, Codable, CaseIterable {
    case bss = "BSS"
    case aprs = "APRS"
    
    /// Convert from protocol integer value
    public static func fromProtocolValue(_ value: Int) -> PacketFormat {
        switch value {
        case 0: return .bss
        case 1: return .aprs
        default: return .bss
        }
    }
    
    /// Convert to protocol integer value
    public func toProtocolValue() -> Int {
        switch self {
        case .bss: return 0
        case .aprs: return 1
        }
    }
}

/// Beacon settings
public struct BeaconSettings: Codable, Equatable {
    public let maxFwdTimes: Int
    public let timeToLive: Int
    public let pttReleaseSendLocation: Bool
    public let pttReleaseSendIDInfo: Bool
    public let pttReleaseSendBSSUserID: Bool
    public let shouldShareLocation: Bool
    public let sendPwrVoltage: Bool
    public let packetFormat: PacketFormat
    public let allowPositionCheck: Bool
    public let aprsSSID: Int
    public let locationShareInterval: Int
    public let bssUserID: Int
    public let pttReleaseIDInfo: String
    public let beaconMessage: String
    public let aprsSymbol: String
    public let aprsCallsign: String
    
    public init(
        maxFwdTimes: Int,
        timeToLive: Int,
        pttReleaseSendLocation: Bool,
        pttReleaseSendIDInfo: Bool,
        pttReleaseSendBSSUserID: Bool,
        shouldShareLocation: Bool,
        sendPwrVoltage: Bool,
        packetFormat: PacketFormat,
        allowPositionCheck: Bool,
        aprsSSID: Int,
        locationShareInterval: Int,
        bssUserID: Int,
        pttReleaseIDInfo: String,
        beaconMessage: String,
        aprsSymbol: String,
        aprsCallsign: String
    ) {
        self.maxFwdTimes = maxFwdTimes
        self.timeToLive = timeToLive
        self.pttReleaseSendLocation = pttReleaseSendLocation
        self.pttReleaseSendIDInfo = pttReleaseSendIDInfo
        self.pttReleaseSendBSSUserID = pttReleaseSendBSSUserID
        self.shouldShareLocation = shouldShareLocation
        self.sendPwrVoltage = sendPwrVoltage
        self.packetFormat = packetFormat
        self.allowPositionCheck = allowPositionCheck
        self.aprsSSID = aprsSSID
        self.locationShareInterval = locationShareInterval
        self.bssUserID = bssUserID
        self.pttReleaseIDInfo = pttReleaseIDInfo
        self.beaconMessage = beaconMessage
        self.aprsSymbol = aprsSymbol
        self.aprsCallsign = aprsCallsign
    }
    public static func empty() -> BeaconSettings {
        return BeaconSettings(
            maxFwdTimes: 0,
            timeToLive: 0,
            pttReleaseSendLocation: false,
            pttReleaseSendIDInfo: false,
            pttReleaseSendBSSUserID: false,
            shouldShareLocation: false,
            sendPwrVoltage: false,
            packetFormat: .bss,
            allowPositionCheck: false,
            aprsSSID: 0,
            locationShareInterval: 0,
            bssUserID: 0,
            pttReleaseIDInfo: "",
            beaconMessage: "",
            aprsSymbol: "",
            aprsCallsign: ""
        )
    }
}

