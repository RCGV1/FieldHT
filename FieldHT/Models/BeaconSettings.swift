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
    // Retained from the radio so writes preserve bits FieldHT does not model yet.
    var rawProtocolPayload: Data?
    public var maxFwdTimes: Int
    public var timeToLive: Int
    public var pttReleaseSendLocation: Bool
    public var pttReleaseSendIDInfo: Bool
    public var pttReleaseSendBSSUserID: Bool
    public var shouldShareLocation: Bool
    public var sendPwrVoltage: Bool
    public var packetFormat: PacketFormat
    public var allowPositionCheck: Bool
    public var aprsSSID: Int
    public var smartBeaconEnabled: Bool
    public var micEEnabled: Bool
    public var sendIDByAPRS: Bool
    public var smartBeaconMinimumInterval: Int?
    public var smartBeaconMaximumInterval: Int?
    public var locationShareInterval: Int
    public var bssUserID: Int
    public var pttReleaseIDInfo: String
    public var beaconMessage: String
    public var aprsSymbol: String
    public var aprsCallsign: String
    
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
        aprsCallsign: String,
        smartBeaconEnabled: Bool = false,
        micEEnabled: Bool = false,
        sendIDByAPRS: Bool = false,
        smartBeaconMinimumInterval: Int? = nil,
        smartBeaconMaximumInterval: Int? = nil
    ) {
        self.rawProtocolPayload = nil
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
        self.smartBeaconEnabled = smartBeaconEnabled
        self.micEEnabled = micEEnabled
        self.sendIDByAPRS = sendIDByAPRS
        self.smartBeaconMinimumInterval = smartBeaconMinimumInterval
        self.smartBeaconMaximumInterval = smartBeaconMaximumInterval
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
            aprsCallsign: "",
            smartBeaconEnabled: false,
            micEEnabled: false,
            sendIDByAPRS: false,
            smartBeaconMinimumInterval: nil,
            smartBeaconMaximumInterval: nil
        )
    }
}
