import Foundation

/// Radio settings
public struct Settings: Codable, Equatable {
    public var channelA: Int
    public var channelB: Int
    public var scan: Bool
    public var aghfpCallMode: Int
    public var doubleChannel: Int
    public var squelchLevel: Int
    public var tailElim: Bool
    public var autoRelayEn: Bool
    public var autoPowerOn: Bool
    public var keepAghfpLink: Bool
    public var micGain: Int
    public var txHoldTime: Int
    public var txTimeLimit: Int
    public var localSpeaker: Int
    public var btMicGain: Int
    public var adaptiveResponse: Bool
    public var disTone: Bool
    public var powerSavingMode: Bool
    public var autoPowerOff: Int
    public var autoShareLocCh: Int? // nil means "current"
    public var hmSpeaker: Int
    public var positioningSystem: Int
    public var timeOffset: Int
    public var useFreqRange2: Bool
    public var pttLock: Bool
    public var leadingSyncBitEn: Bool
    public var pairingAtPowerOn: Bool
    public var screenTimeout: Int
    public var vfoX: Int
    public var imperialUnit: Bool
    public var wxMode: Int
    public var noaaCh: Int
    public var vfo1TxPowerX: Int
    public var vfo2TxPowerX: Int
    public var disDigitalMute: Bool
    public var signalingEccEn: Bool
    public var chDataLock: Bool
    public var kissTxDelay: Int
    public var kissTxTail: Int
    public var voxEnabled: Bool
    public var voxLevel: Int
    public var disableBluetoothMic: Bool
    public var voxDelay: Int
    public var noiseSuppressionEnabled: Bool
    /// Preserves a firmware field with no verified public behavior.
    public var reservedAlarmVolume: Int
    public var useCustomLocation: Bool
    public var gpwplUploadEnabled: Bool
    public var vfo1ModFreqX: Int
    // Retained for source compatibility with older app builds. These bits are not part of the current settings prefix.
    public var vfo2ModFreqX: Int
    public var reservedExt1: Int // Unknown 2 bytes at end
    /// Bytes after the fixed settings prefix, retained so custom location data is not overwritten.
    public var rawExtensionData: Data
    
    public init(
        channelA: Int,
        channelB: Int,
        scan: Bool,
        aghfpCallMode: Int,
        doubleChannel: Int,
        squelchLevel: Int,
        tailElim: Bool,
        autoRelayEn: Bool,
        autoPowerOn: Bool,
        keepAghfpLink: Bool,
        micGain: Int,
        txHoldTime: Int,
        txTimeLimit: Int,
        localSpeaker: Int,
        btMicGain: Int,
        adaptiveResponse: Bool,
        disTone: Bool,
        powerSavingMode: Bool,
        autoPowerOff: Int,
        autoShareLocCh: Int?,
        hmSpeaker: Int,
        positioningSystem: Int,
        timeOffset: Int,
        useFreqRange2: Bool,
        pttLock: Bool,
        leadingSyncBitEn: Bool,
        pairingAtPowerOn: Bool,
        screenTimeout: Int,
        vfoX: Int,
        imperialUnit: Bool,
        wxMode: Int,
        noaaCh: Int,
        vfo1TxPowerX: Int,
        vfo2TxPowerX: Int,
        disDigitalMute: Bool,
        signalingEccEn: Bool,
        chDataLock: Bool,
        vfo1ModFreqX: Int,
        vfo2ModFreqX: Int,
        reservedExt1: Int = 0,
        kissTxDelay: Int = 0,
        kissTxTail: Int = 0,
        voxEnabled: Bool = false,
        voxLevel: Int = 0,
        disableBluetoothMic: Bool = false,
        voxDelay: Int = 0,
        noiseSuppressionEnabled: Bool = false,
        reservedAlarmVolume: Int = 0,
        useCustomLocation: Bool = false,
        gpwplUploadEnabled: Bool = false,
        rawExtensionData: Data = Data()
    ) {
        self.channelA = channelA
        self.channelB = channelB
        self.scan = scan
        self.aghfpCallMode = aghfpCallMode
        self.doubleChannel = doubleChannel
        self.squelchLevel = squelchLevel
        self.tailElim = tailElim
        self.autoRelayEn = autoRelayEn
        self.autoPowerOn = autoPowerOn
        self.keepAghfpLink = keepAghfpLink
        self.micGain = micGain
        self.txHoldTime = txHoldTime
        self.txTimeLimit = txTimeLimit
        self.localSpeaker = localSpeaker
        self.btMicGain = btMicGain
        self.adaptiveResponse = adaptiveResponse
        self.disTone = disTone
        self.powerSavingMode = powerSavingMode
        self.autoPowerOff = autoPowerOff
        self.autoShareLocCh = autoShareLocCh
        self.hmSpeaker = hmSpeaker
        self.positioningSystem = positioningSystem
        self.timeOffset = timeOffset
        self.useFreqRange2 = useFreqRange2
        self.pttLock = pttLock
        self.leadingSyncBitEn = leadingSyncBitEn
        self.pairingAtPowerOn = pairingAtPowerOn
        self.screenTimeout = screenTimeout
        self.vfoX = vfoX
        self.imperialUnit = imperialUnit
        self.wxMode = wxMode
        self.noaaCh = noaaCh
        self.vfo1TxPowerX = vfo1TxPowerX
        self.vfo2TxPowerX = vfo2TxPowerX
        self.disDigitalMute = disDigitalMute
        self.signalingEccEn = signalingEccEn
        self.chDataLock = chDataLock
        self.kissTxDelay = kissTxDelay
        self.kissTxTail = kissTxTail
        self.voxEnabled = voxEnabled
        self.voxLevel = voxLevel
        self.disableBluetoothMic = disableBluetoothMic
        self.voxDelay = voxDelay
        self.noiseSuppressionEnabled = noiseSuppressionEnabled
        self.reservedAlarmVolume = reservedAlarmVolume
        self.useCustomLocation = useCustomLocation
        self.gpwplUploadEnabled = gpwplUploadEnabled
        self.vfo1ModFreqX = vfo1ModFreqX
        self.vfo2ModFreqX = vfo2ModFreqX
        self.reservedExt1 = reservedExt1
        self.rawExtensionData = rawExtensionData
    }

    /// The protocol stores the two KISS flags in the legacy `vfoX` bit field.
    public var kissUploadTxMessage: Bool {
        get { (vfoX & 0b10) != 0 }
        set { vfoX = (vfoX & ~0b10) | (newValue ? 0b10 : 0) }
    }

    public var kissEnabled: Bool {
        get { (vfoX & 0b01) != 0 }
        set { vfoX = (vfoX & ~0b01) | (newValue ? 0b01 : 0) }
    }

    public static func empty() -> Settings {
        return Settings(
            channelA: 0,
            channelB: 0,
            scan: false,
            aghfpCallMode: 0,
            doubleChannel: 1,
            squelchLevel: 0,
            tailElim: false,
            autoRelayEn: false,
            autoPowerOn: false,
            keepAghfpLink: false,
            micGain: 0,
            txHoldTime: 0,
            txTimeLimit: 0,
            localSpeaker: 0,
            btMicGain: 0,
            adaptiveResponse: false,
            disTone: false,
            powerSavingMode: false,
            autoPowerOff: 0,
            autoShareLocCh: nil,
            hmSpeaker: 0,
            positioningSystem: 0,
            timeOffset: 0,
            useFreqRange2: false,
            pttLock: false,
            leadingSyncBitEn: false,
            pairingAtPowerOn: false,
            screenTimeout: 0,
            vfoX: 0,
            imperialUnit: false,
            wxMode: 0,
            noaaCh: 0,
            vfo1TxPowerX: 0,
            vfo2TxPowerX: 0,
            disDigitalMute: false,
            signalingEccEn: false,
            chDataLock: false,
            vfo1ModFreqX: 0,
            vfo2ModFreqX: 0
        )
    }
}
