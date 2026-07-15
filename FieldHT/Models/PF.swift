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

/// Programmable Function button effect type.
/// Keep this open-ended so newer firmware effect IDs can round-trip.
public struct PFEffectType: RawRepresentable, Codable, Hashable, Equatable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let disable = PFEffectType(rawValue: 0)
    public static let alarm = PFEffectType(rawValue: 1)
    public static let alarmAndMute = PFEffectType(rawValue: 2)
    public static let toggleOffline = PFEffectType(rawValue: 3)
    public static let toggleRadioTx = PFEffectType(rawValue: 4)
    public static let toggleTxPower = PFEffectType(rawValue: 5)
    public static let toggleFM = PFEffectType(rawValue: 6)
    public static let prevChannel = PFEffectType(rawValue: 7)
    public static let nextChannel = PFEffectType(rawValue: 8)
    public static let tCall = PFEffectType(rawValue: 9)
    public static let prevRegion = PFEffectType(rawValue: 10)
    public static let nextRegion = PFEffectType(rawValue: 11)
    public static let toggleChScan = PFEffectType(rawValue: 12)
    public static let mainPTT = PFEffectType(rawValue: 13)
    public static let subPTT = PFEffectType(rawValue: 14)
    public static let toggleMonitor = PFEffectType(rawValue: 15)
    public static let btPairing = PFEffectType(rawValue: 16)
    public static let toggleDoubleCh = PFEffectType(rawValue: 17)
    public static let toggleABCh = PFEffectType(rawValue: 18)
    public static let sendLocation = PFEffectType(rawValue: 19)
    public static let oneClickLink = PFEffectType(rawValue: 20)
    public static let volDown = PFEffectType(rawValue: 21)
    public static let volUp = PFEffectType(rawValue: 22)
    public static let toggleMute = PFEffectType(rawValue: 23)

    public static let knownCases: [PFEffectType] = [
        .disable, .alarm, .alarmAndMute, .toggleOffline, .toggleRadioTx, .toggleTxPower,
        .toggleFM, .prevChannel, .nextChannel, .tCall, .prevRegion, .nextRegion,
        .toggleChScan, .mainPTT, .subPTT, .toggleMonitor, .btPairing,
        .toggleDoubleCh, .toggleABCh, .sendLocation, .oneClickLink,
        .volDown, .volUp, .toggleMute
    ]

    public var isKnown: Bool {
        Self.knownCases.contains(self)
    }

    public var displayName: String {
        switch rawValue {
        case 0: return "Disable"
        case 1: return "Alarm"
        case 2: return "Alarm and Mute"
        case 3: return "Toggle Talk Around"
        case 4: return "Toggle Radio TX"
        case 5: return "Toggle TX Power"
        case 6: return "Toggle FM"
        case 7: return "Previous Channel"
        case 8: return "Next Channel"
        case 9: return "T-Call"
        case 10: return "Previous Group"
        case 11: return "Next Group"
        case 12: return "Toggle Channel Scan"
        case 13: return "Main PTT"
        case 14: return "Sub PTT"
        case 15: return "Toggle Monitor"
        case 16: return "BT Pairing"
        case 17: return "Toggle Double Channel"
        case 18: return "Toggle A/B Channel"
        case 19: return "Send Location"
        case 20: return "One Click Link"
        case 21: return "Volume Down"
        case 22: return "Volume Up"
        case 23: return "Toggle Mute"
        case 24: return "Unknown Action 24"
        case 25: return "Unknown Action 25"
        case 27: return "Unknown Action 27"
        case 28: return "Unknown Action 28"
        case 29: return "Unknown Action 29"
        case 30: return "Unknown Action 30"
        case 31: return "Unknown Action 31"
        default: return "Unknown Action \(rawValue)"
        }
    }

    public var shortName: String {
        switch rawValue {
        case 0: return "Disable"
        case 1: return "Alarm"
        case 2: return "Alarm+Mute"
        case 3: return "Talk Around"
        case 4: return "Radio TX"
        case 5: return "TX Power"
        case 6: return "FM"
        case 7: return "Prev Ch"
        case 8: return "Next Ch"
        case 9: return "T-Call"
        case 10: return "Prev Group"
        case 11: return "Next Group"
        case 12: return "Ch Scan"
        case 13: return "Main PTT"
        case 14: return "Sub PTT"
        case 15: return "Monitor"
        case 16: return "BT Pair"
        case 17: return "Double Ch"
        case 18: return "A/B"
        case 19: return "Send Loc"
        case 20: return "One Click"
        case 21: return "Vol-"
        case 22: return "Vol+"
        case 23: return "Mute"
        default: return "Action \(rawValue)"
        }
    }
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
