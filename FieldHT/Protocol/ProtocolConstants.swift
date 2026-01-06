import Foundation
import CoreBluetooth

/// BLE Service UUID
public let radioServiceUUID = CBUUID(string: "00001100-D102-11E1-9B23-00025B00A5A5")

/// BLE Write Characteristic UUID
public let radioWriteUUID = CBUUID(string: "00001101-d102-11e1-9b23-00025b00a5a5")

/// BLE Indicate Characteristic UUID
public let radioIndicateUUID = CBUUID(string: "00001102-d102-11e1-9b23-00025b00a5a5")

public let radioPairingUUID = CBUUID(string: "88A1")

/// Command groups
public enum CommandGroup: UInt8 {
    case basic = 2
    case extended = 10
}

/// Basic commands
public enum BasicCommand: UInt16 {
    case unknown = 0
    case getDevID = 1
    case getDevInfo = 4
    case readStatus = 5
    case registerNotification = 6
    case cancelNotification = 7
    case readSettings = 10
    case writeSettings = 11
    case readRFCh = 13
    case writeRFCh = 14
    case getHTStatus = 20
    case htSendData = 31
    case readBSSSettings = 33
    case writeBSSSettings = 34
    case freqModeSetPar = 35
    case freqModeGetStatus = 36
    case readRDA1846S_AGC = 37
    case writeRDA1846S_AGC = 38
    case readFreqRange = 39
    case writeDeEmphCoeffs = 40
    case stopRinging = 41
    case setTxTimeLimit = 42
    case setIsDigitalSignal = 43
    case setHL = 44
    case setDID = 45
    case setIBA = 46
    case getIBA = 47
    case setTrustedDeviceName = 48
    case setVOC = 49
    case getVOC = 50
    case setPhoneStatus = 51
    case readRFStatus = 52
    case playTone = 53
    case getDID = 54
    case getPF = 55
    case setPF = 56
    case rxData = 57
    case writeRegionCh = 58
    case writeRegionName = 59
    case setRegion = 60
    case setPP_ID = 61
    case getPP_ID = 62
    case readAdvancedSettings2 = 63
    case writeAdvancedSettings2 = 64
    case unlock = 65
    case doProgFunc = 66
    case setMSG = 67
    case getMSG = 68
    case bleConnParam = 69
    case setTime = 70
    case setAPRSPath = 71
    case getAPRSPath = 72
    case readRegionName = 73
    case setDevID = 74
    case getPFActions = 75
    case getPosition = 76
    case eventNotification = 9
}

/// Reply status
public enum ReplyStatus: UInt8 {
    case success = 0
    case notSupported = 1
    case notAuthenticated = 2
    case insufficientResources = 3
    case authenticating = 4
    case invalidParameter = 5
    case incorrectState = 6
    case inProgress = 7
}

/// Event types (CRITICAL: Values must match Python benlink!)
public enum EventType: UInt8 {
    case unknown = 0
    case htStatusChanged = 1      // HT_STATUS_CHANGED
    case dataRxd = 2              // DATA_RXD
    case newInquiryData = 3       // NEW_INQUIRY_DATA
    case restoreFactorySettings = 4  // RESTORE_FACTORY_SETTINGS
    case htChChanged = 5          // HT_CH_CHANGED
    case htSettingsChanged = 6    // HT_SETTINGS_CHANGED
    case ringingStopped = 7       // RINGING_STOPPED
    case radioStatusChanged = 8   // RADIO_STATUS_CHANGED
    case userAction = 9           // USER_ACTION
    case systemEvent = 10         // SYSTEM_EVENT
    case bssSettingsChanged = 11  // BSS_SETTINGS_CHANGED
    case dataTxd = 12             // DATA_TXD
    case positionChanged = 13     // POSITION_CHANGE
}

