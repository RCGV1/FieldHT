import Foundation

/// Programmable Function button action type
public enum PFActionType: Int, Codable, CaseIterable {
    case invalid = 0
    case short = 1
    case long = 2
    case veryLong = 3
    case double = 4
    case `repeat` = 5  // Escaped because 'repeat' is a Swift keyword
    case lowToHigh = 6
    case highToLow = 7
    case shortSingle = 8
    case longRelease = 9
    case veryLongRelease = 10
    case veryVeryLong = 11
    case veryVeryLongRelease = 12
    case triple = 13
}

/// Programmable Function button effect type
public enum PFEffectType: Int, Codable {
    case disable = 0
    case alarm = 1
    case alarmAndMute = 2
    case toggleOffline = 3
    case toggleRadioTx = 4
    case toggleTxPower = 5
    case toggleFM = 6
    case prevChannel = 7
    case nextChannel = 8
    case tCall = 9
    case prevRegion = 10
    case nextRegion = 11
    case toggleChScan = 12
    case mainPTT = 13
    case subPTT = 14
    case toggleMonitor = 15
    case btPairing = 16
    case toggleDoubleCh = 17
    case toggleABCh = 18
    case sendLocation = 19
    case oneClickLink = 20
    case volDown = 21
    case volUp = 22
    case toggleMute = 23
}

/// Programmable Function button configuration
public struct PF: Codable, Equatable {
    public var buttonID: Int  // 4 bits
    public var action: PFActionType
    public var effect: PFEffectType
    
    public init(buttonID: Int, action: PFActionType, effect: PFEffectType) {
        self.buttonID = buttonID
        self.action = action
        self.effect = effect
    }
}

/// Collection of Programmable Functions (device-defined length)
public struct PFConfig: Codable, Equatable {
    public var pf: [PF]
     
    public init(pf: [PF]) {
        self.pf = pf
    }
     
    public init() {
        self.pf = []
    }
}
