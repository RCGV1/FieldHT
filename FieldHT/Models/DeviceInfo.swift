import Foundation

/// Device information from the radio
public struct DeviceInfo: Codable, Equatable {
    public let vendorID: Int
    public let productID: Int
    public let hardwareVersion: Int
    public let firmwareVersion: Int
    public let supportsRadio: Bool
    public let supportsMediumPower: Bool
    public let fixedLocationSpeakerVolume: Bool
    public let supportsSoftwarePowerControl: Bool
    public let hasSpeaker: Bool
    public let hasHandMicrophoneSpeaker: Bool
    public let regionCount: Int
    public let supportsNOAA: Bool
    public let supportsGMRS: Bool
    public let supportsVFO: Bool
    public let supportsDMR: Bool
    public let channelCount: Int
    public let frequencyRangeCount: Int
    
    public init(
        vendorID: Int,
        productID: Int,
        hardwareVersion: Int,
        firmwareVersion: Int,
        supportsRadio: Bool,
        supportsMediumPower: Bool,
        fixedLocationSpeakerVolume: Bool,
        supportsSoftwarePowerControl: Bool,
        hasSpeaker: Bool,
        hasHandMicrophoneSpeaker: Bool,
        regionCount: Int,
        supportsNOAA: Bool,
        supportsGMRS: Bool,
        supportsVFO: Bool,
        supportsDMR: Bool,
        channelCount: Int,
        frequencyRangeCount: Int
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.hardwareVersion = hardwareVersion
        self.firmwareVersion = firmwareVersion
        self.supportsRadio = supportsRadio
        self.supportsMediumPower = supportsMediumPower
        self.fixedLocationSpeakerVolume = fixedLocationSpeakerVolume
        self.supportsSoftwarePowerControl = supportsSoftwarePowerControl
        self.hasSpeaker = hasSpeaker
        self.hasHandMicrophoneSpeaker = hasHandMicrophoneSpeaker
        self.regionCount = regionCount
        self.supportsNOAA = supportsNOAA
        self.supportsGMRS = supportsGMRS
        self.supportsVFO = supportsVFO
        self.supportsDMR = supportsDMR
        self.channelCount = channelCount
        self.frequencyRangeCount = frequencyRangeCount
    }
    public static func empty() -> DeviceInfo {
        return DeviceInfo(
            vendorID: 0,
            productID: 0,
            hardwareVersion: 0,
            firmwareVersion: 0,
            supportsRadio: false,
            supportsMediumPower: false,
            fixedLocationSpeakerVolume: false,
            supportsSoftwarePowerControl: false,
            hasSpeaker: false,
            hasHandMicrophoneSpeaker: false,
            regionCount: 0,
            supportsNOAA: false,
            supportsGMRS: false,
            supportsVFO: false,
            supportsDMR: false,
            channelCount: 0,
            frequencyRangeCount: 0
        )
    }
}

