import Foundation

/// Channel type
public enum ChannelType: String, Codable, CaseIterable {
    case off = "OFF"
    case a = "A"
    case b = "B"
    
    /// Convert from protocol integer value
    public static func fromProtocolValue(_ value: Int) -> ChannelType {
        switch value {
        case 0: return .off
        case 1: return .a
        case 2: return .b
        default: return .off
        }
    }
    
    /// Convert to protocol integer value
    public func toProtocolValue() -> Int {
        switch self {
        case .off: return 0
        case .a: return 1
        case .b: return 2
        }
    }
}

/// Radio status
public struct Status: Codable, Equatable {
    public let isPowerOn: Bool
    public let isInTx: Bool
    public let isSq: Bool
    public let isInRx: Bool
    public let doubleChannel: ChannelType
    public let isScan: Bool
    public let isRadio: Bool
    public let currChID: Int
    public let isGPSLocked: Bool
    public let isHFPConnected: Bool
    public let isAOCConnected: Bool
    public let rssi: Double
    public var currRegion: Int
    public let currChIDUpper: Int
    public let currChIDLower: Int
    
    public init(
        isPowerOn: Bool,
        isInTx: Bool,
        isSq: Bool,
        isInRx: Bool,
        doubleChannel: ChannelType,
        isScan: Bool,
        isRadio: Bool,
        currChID: Int,
        isGPSLocked: Bool,
        isHFPConnected: Bool,
        isAOCConnected: Bool,
        rssi: Double,
        currRegion: Int,
        currChIDUpper: Int,
        currChIDLower: Int
    ) {
        self.isPowerOn = isPowerOn
        self.isInTx = isInTx
        self.isSq = isSq
        self.isInRx = isInRx
        self.doubleChannel = doubleChannel
        self.isScan = isScan
        self.isRadio = isRadio
        self.currChID = currChID
        self.isGPSLocked = isGPSLocked
        self.isHFPConnected = isHFPConnected
        self.isAOCConnected = isAOCConnected
        self.rssi = rssi
        self.currRegion = currRegion
        self.currChIDUpper = currChIDUpper
        self.currChIDLower = currChIDLower
    }
    public static func empty() -> Status {
        return Status(
            isPowerOn: false,
            isInTx: false,
            isSq: false,
            isInRx: false,
            doubleChannel: .off,
            isScan: false,
            isRadio: false,
            currChID: 0,
            isGPSLocked: false,
            isHFPConnected: false,
            isAOCConnected: false,
            rssi: 0.0,
            currRegion: 0,
            currChIDUpper: 0,
            currChIDLower: 0
        )
    }
}

