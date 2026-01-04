import Foundation

/// Snapshot of the radio state
public struct RadioState: Equatable {
    public let deviceInfo: DeviceInfo
    public var beaconSettings: BeaconSettings
    public var status: Status
    public var settings: Settings
    public var regionNames: [String]
    
    public init(
        deviceInfo: DeviceInfo,
        beaconSettings: BeaconSettings,
        status: Status,
        settings: Settings,
        regionNames: [String]
    ) {
        self.deviceInfo = deviceInfo
        self.beaconSettings = beaconSettings
        self.status = status
        self.settings = settings
        self.regionNames = regionNames
    }
}
