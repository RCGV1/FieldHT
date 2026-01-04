import Foundation

/// Protocol message decoder - converts raw protocol bytes to Swift models
public struct ProtocolDecoder {
    
    // MARK: - Message Decoding
    
    public static func decodeMessage(_ data: Data) throws -> ProtocolMessage {
        var stream = BitStream(data: data)
        
        let commandGroupRaw = try stream.readInt(16)
        guard let commandGroup = CommandGroup(rawValue: UInt8(commandGroupRaw)) else {
            throw ProtocolError.invalidCommandGroup
        }
        
        let isReply = try stream.readBool()
        let command = try stream.readInt(15)
        
        let bodyData = try stream.readBytes(stream.remaining / 8)
        
        return ProtocolMessage(
            commandGroup: commandGroup,
            isReply: isReply,
            command: UInt16(command),
            body: bodyData
        )
    }
    
    // MARK: - Device Info Decoding
    
    public static func decodeDeviceInfo(_ data: Data) throws -> DeviceInfo {
        var stream = BitStream(data: data)
        
        let vendorID = try stream.readInt(8)
        let productID = try stream.readInt(16)
        let hwVer = try stream.readInt(8)
        let softVer = try stream.readInt(16)
        let supportRadio = try stream.readBool()
        let supportMediumPower = try stream.readBool()
        let fixedLocSpeakerVol = try stream.readBool()
        let notSupportSoftPowerCtrl = try stream.readBool()
        let haveNoSpeaker = try stream.readBool()
        let haveHmSpeaker = try stream.readBool()
        let regionCount = try stream.readInt(6)
        let supportNoaa = try stream.readBool()
        let gmrs = try stream.readBool()
        let supportVfo = try stream.readBool()
        let supportDmr = try stream.readBool()
        let channelCount = try stream.readInt(8)
        let freqRangeCount = try stream.readInt(4)
        let supportNoiseReduction = try stream.readBool()
        let supportSmartBeacon = try stream.readBool()
        _ = try stream.readInt(2) // pad
        
        return DeviceInfo(
            vendorID: vendorID,
            productID: productID,
            hardwareVersion: hwVer,
            firmwareVersion: softVer,
            supportsRadio: supportRadio,
            supportsMediumPower: supportMediumPower,
            fixedLocationSpeakerVolume: fixedLocSpeakerVol,
            supportsSoftwarePowerControl: !notSupportSoftPowerCtrl,
            hasSpeaker: !haveNoSpeaker,
            hasHandMicrophoneSpeaker: haveHmSpeaker,
            regionCount: regionCount,
            supportsNOAA: supportNoaa,
            supportsGMRS: gmrs,
            supportsVFO: supportVfo,
            supportsDMR: supportDmr,
            channelCount: channelCount,
            frequencyRangeCount: freqRangeCount
        )
    }
    
    // MARK: - Channel Decoding
    
    public static func decodeChannel(_ data: Data, supportsDMR: Bool = false) throws -> Channel {
        var stream = BitStream(data: data)
        
        let channelID = try stream.readInt(8)
        let txModRaw = try stream.readInt(2)
        let txMod = ModulationType.fromProtocolValue(txModRaw)
        let txFreqRaw = try stream.readInt(30)
        let txFreq = Double(txFreqRaw) * 1e-6
        let rxModRaw = try stream.readInt(2)
        let rxMod = ModulationType.fromProtocolValue(rxModRaw)
        let rxFreqRaw = try stream.readInt(30)
        let rxFreq = Double(rxFreqRaw) * 1e-6
        
        // Sub-audio decoding
        let txSubAudioRaw = try stream.readInt(16)
        let txSubAudio = decodeSubAudio(txSubAudioRaw)
        let rxSubAudioRaw = try stream.readInt(16)
        let rxSubAudio = decodeSubAudio(rxSubAudioRaw)
        
        let scan = try stream.readBool()
        let txAtMaxPower = try stream.readBool()
        let talkAround = try stream.readBool()
        let bandwidthRaw = try stream.readInt(1)
        let bandwidth = BandwidthType.fromProtocolValue(bandwidthRaw)
        let preDeEmphBypass = try stream.readBool()
        let sign = try stream.readBool()
        let txAtMedPower = try stream.readBool()
        let txDisable = try stream.readBool()
        let fixedFreq = try stream.readBool()
        let fixedBandwidth = try stream.readBool()
        let fixedTxPower = try stream.readBool()
        let mute = try stream.readBool()
        _ = try stream.readInt(4) // pad / reserved


        
        // Name (10 bytes)
        let nameData = try stream.readBytes(10)
        let name = String(data: nameData, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? ""

        return Channel(
            channelID: channelID,
            txMod: txMod,
            txFreq: txFreq,
            rxMod: rxMod,
            rxFreq: rxFreq,
            txSubAudio: txSubAudio,
            rxSubAudio: rxSubAudio,
            scan: scan,
            txAtMaxPower: txAtMaxPower,
            talkAround: talkAround,
            bandwidth: bandwidth,
            preDeEmphBypass: preDeEmphBypass,
            sign: sign,
            txAtMedPower: txAtMedPower,
            txDisable: txDisable,
            fixedFreq: fixedFreq,
            fixedBandwidth: fixedBandwidth,
            fixedTxPower: fixedTxPower,
            mute: mute,
            name: name
        )
    }
    
    private static func decodeSubAudio(_ value: Int) -> SubAudio? {
        if value == 0 {
            return nil
        }
        if value < 6700 {
            return .dcs(DCS(n: value))
        }
        return .frequency(Double(value) / 100.0)
    }
    
    // MARK: - Status Decoding
    
    public static func decodeStatus(_ data: Data) throws -> Status {
        var stream = BitStream(data: data)
        
        let isPowerOn = try stream.readBool()
        let isInTx = try stream.readBool()
        let isSq = try stream.readBool()
        let isInRx = try stream.readBool()
        let doubleChannelRaw = try stream.readInt(2)
        let doubleChannel = ChannelType.fromProtocolValue(doubleChannelRaw)
        let isScan = try stream.readBool()
        let isRadio = try stream.readBool()
        var currChIDLower = try stream.readInt(4)
        let isGPSLocked = try stream.readBool()
        let isHFPConnected = try stream.readBool()
        let isAOCConnected = try stream.readBool()
        let unknown = try stream.readInt(1)
        
        // Check if extended status
        var currChIDUpper = 0
        var rssi: Double = 0
        var currRegion = 0
        
        if stream.remaining >= 16 {
            let rssiRaw = try stream.readInt(4)
            // RSSI is scaled: raw * (100/15) gives a value 0-100 representing signal strength
            rssi = Double(rssiRaw) * (100.0 / 15.0)
            print("[DECODE] RSSI raw: \(rssiRaw), calculated: \(rssi)")
            currRegion = try stream.readInt(6)
            currChIDUpper = try stream.readInt(4)
            _ = try stream.readInt(2) // pad
        }
        
        let currChID = (currChIDUpper << 4) | currChIDLower
       
        return Status(
            isPowerOn: isPowerOn,
            isInTx: isInTx,
            isSq: isSq,
            isInRx: isInRx,
            doubleChannel: doubleChannel,
            isScan: isScan,
            isRadio: isRadio,
            currChID: currChID,
            isGPSLocked: isGPSLocked,
            isHFPConnected: isHFPConnected,
            isAOCConnected: isAOCConnected,
            rssi: rssi,
            currRegion: currRegion,
            currChIDUpper: currChIDUpper,
            currChIDLower: currChIDLower
        )
    }
    
    // MARK: - Settings Decoding
    
    public static func decodeSettings(_ data: Data) throws -> Settings {
        var stream = BitStream(data: data)
        
        let channelALower = try stream.readInt(4)
        let channelBLower = try stream.readInt(4)
        let scan = try stream.readBool()
        let aghfpCallMode = try stream.readInt(1)
        let doubleChannel = try stream.readInt(2)
        let squelchLevel = try stream.readInt(4)
        let tailElim = try stream.readBool()
        let autoRelayEn = try stream.readBool()
        let autoPowerOn = try stream.readBool()
        let keepAghfpLink = try stream.readBool()
        let micGain = try stream.readInt(3)
        let txHoldTime = try stream.readInt(4)
        let txTimeLimit = try stream.readInt(5)
        let localSpeaker = try stream.readInt(2)
        let btMicGain = try stream.readInt(3)
        let adaptiveResponse = try stream.readBool()
        let disTone = try stream.readBool()
        let powerSavingMode = try stream.readBool()
        let autoPowerOff = try stream.readInt(3)
        
        // auto_share_loc_ch (5 bits, mapped)
        let autoShareLocChRaw = try stream.readInt(5)
        let autoShareLocCh: Int? = autoShareLocChRaw > 0 ? autoShareLocChRaw - 1 : nil
        
        let hmSpeaker = try stream.readInt(2)
        let positioningSystem = try stream.readInt(4)
        let timeOffset = try stream.readInt(6)
        let useFreqRange2 = try stream.readBool()
        let pttLock = try stream.readBool()
        let leadingSyncBitEn = try stream.readBool()
        let pairingAtPowerOn = try stream.readBool()
        let screenTimeout = try stream.readInt(5)
        let vfoX = try stream.readInt(2)
        let imperialUnit = try stream.readBool()
        let channelAUpper = try stream.readInt(4)
        let channelBUpper = try stream.readInt(4)
        let wxMode = try stream.readInt(2)
        let noaaCh = try stream.readInt(4)
        let vfo1TxPowerX = try stream.readInt(2)
        let vfo2TxPowerX = try stream.readInt(2)
        let disDigitalMute = try stream.readBool()
        let signalingEccEn = try stream.readBool()
        let chDataLock = try stream.readBool()
        _ = try stream.readInt(3) // pad
        let vfo1ModFreqX = try stream.readInt(32)
        let vfo2ModFreqX = try stream.readInt(32)
        
        var reservedExt1 = 0
        if stream.remaining >= 16 {
            reservedExt1 = try stream.readInt(16)
        }
        
        let channelA = (channelAUpper << 4) | channelALower
        let channelB = (channelBUpper << 4) | channelBLower
        
        return Settings(
            channelA: channelA,
            channelB: channelB,
            scan: scan,
            aghfpCallMode: aghfpCallMode,
            doubleChannel: doubleChannel,
            squelchLevel: squelchLevel,
            tailElim: tailElim,
            autoRelayEn: autoRelayEn,
            autoPowerOn: autoPowerOn,
            keepAghfpLink: keepAghfpLink,
            micGain: micGain,
            txHoldTime: txHoldTime,
            txTimeLimit: txTimeLimit,
            localSpeaker: localSpeaker,
            btMicGain: btMicGain,
            adaptiveResponse: adaptiveResponse,
            disTone: disTone,
            powerSavingMode: powerSavingMode,
            autoPowerOff: autoPowerOff,
            autoShareLocCh: autoShareLocCh,
            hmSpeaker: hmSpeaker,
            positioningSystem: positioningSystem,
            timeOffset: timeOffset,
            useFreqRange2: useFreqRange2,
            pttLock: pttLock,
            leadingSyncBitEn: leadingSyncBitEn,
            pairingAtPowerOn: pairingAtPowerOn,
            screenTimeout: screenTimeout,
            vfoX: vfoX,
            imperialUnit: imperialUnit,
            wxMode: wxMode,
            noaaCh: noaaCh,
            vfo1TxPowerX: vfo1TxPowerX,
            vfo2TxPowerX: vfo2TxPowerX,
            disDigitalMute: disDigitalMute,
            signalingEccEn: signalingEccEn,
            chDataLock: chDataLock,
            vfo1ModFreqX: vfo1ModFreqX,
            vfo2ModFreqX: vfo2ModFreqX,
            reservedExt1: reservedExt1
        )
    }
    
    // MARK: - Position Decoding
    
    public static func decodePosition(_ data: Data) throws -> Position {
        var stream = BitStream(data: data)
        
        // Latitude (24 bits signed, then scaled)
        let latRaw = try stream.readInt(24)
        let latSigned = latRaw >= 8388608 ? latRaw - 16777216 : latRaw
        let latitude = Double(latSigned) / 60.0 / 500.0
        
        // Longitude (24 bits signed, then scaled)
        let lonRaw = try stream.readInt(24)
        let lonSigned = lonRaw >= 8388608 ? lonRaw - 16777216 : lonRaw
        let longitude = Double(lonSigned) / 60.0 / 500.0
        
        // Altitude (16 bits signed, optional)
        let altRaw = try stream.readInt(16)
        let altSigned = altRaw >= 32768 ? altRaw - 65536 : altRaw
        let altitude: Int? = altSigned == -32768 ? nil : altSigned
        
        // Speed (16 bits, optional)
        let speedRaw = try stream.readInt(16)
        let speed: Int? = speedRaw == 0xFFFF ? nil : speedRaw
        
        // Heading (16 bits, optional)
        let headingRaw = try stream.readInt(16)
        let heading: Int? = headingRaw == 0xFFFF ? nil : headingRaw
        
        // Time (32 bits, Unix timestamp)
        let timeRaw = try stream.readInt(32)
        let time = Date(timeIntervalSince1970: TimeInterval(timeRaw))
        
        // Accuracy (16 bits)
        let accuracy = try stream.readInt(16)
        
        return Position(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            speed: speed,
            heading: heading,
            time: time,
            accuracy: accuracy
        )
    }
    
    // MARK: - Power Status Decoding
    
    public enum PowerStatusType: Int {
        case unknown = 0
        case batteryLevel = 1
        case batteryVoltage = 2
        case rcBatteryLevel = 3
        case batteryLevelAsPercentage = 4
    }
    
    public static func decodePowerStatus(_ data: Data) throws -> (type: PowerStatusType, value: Any) {
        var stream = BitStream(data: data)
        let statusTypeRaw = try stream.readInt(16)
        guard let statusType = PowerStatusType(rawValue: statusTypeRaw) else {
            throw ProtocolError.invalidPowerStatusType
        }
        
        switch statusType {
        case .batteryVoltage:
            let voltageRaw = try stream.readInt(16)
            let voltage = Double(voltageRaw) / 1000.0
            return (type: statusType, value: voltage)
        case .batteryLevel:
            let level = try stream.readInt(8)
            return (type: statusType, value: level)
        case .batteryLevelAsPercentage:
            let percentage = try stream.readInt(8)
            return (type: statusType, value: percentage)
        case .rcBatteryLevel:
            let rcLevel = try stream.readInt(8)
            return (type: statusType, value: rcLevel)
        case .unknown:
            throw ProtocolError.invalidPowerStatusType
        }
    }
    
    // MARK: - TNC Data Fragment Decoding
    
    public static func decodeTncDataFragment(_ data: Data) throws -> TncDataFragment {
        var stream = BitStream(data: data)
        
        let isFinalFragment = try stream.readBool()
        let withChannelID = try stream.readBool()
        let fragmentID = try stream.readInt(6)
        
        // Data length depends on whether channel_id is present
        let dataByteCount = (stream.remaining / 8) - (withChannelID ? 1 : 0)
        let fragmentData = try stream.readBytes(dataByteCount)
        
        let channelID: Int? = withChannelID ? try stream.readInt(8) : nil
        
        return TncDataFragment(
            isFinalFragment: isFinalFragment,
            fragmentID: fragmentID,
            data: fragmentData,
            channelID: channelID
        )
    }
    
    // MARK: - Beacon Settings Decoding
    
    public static func decodeBeaconSettings(_ data: Data) throws -> BeaconSettings {
        var stream = BitStream(data: data)
        
        let maxFwdTimes = try stream.readInt(4)
        let timeToLive = try stream.readInt(4)
        let pttReleaseSendLocation = try stream.readBool()
        let pttReleaseSendIDInfo = try stream.readBool()
        let pttReleaseSendBSSUserID = try stream.readBool()
        let shouldShareLocation = try stream.readBool()
        let sendPwrVoltage = try stream.readBool()
        let packetFormatRaw = try stream.readInt(1)
        let packetFormat = PacketFormat.fromProtocolValue(packetFormatRaw)
        let allowPositionCheck = try stream.readBool()
        _ = try stream.readInt(1) // pad
        let aprsSSID = try stream.readInt(4)
        _ = try stream.readInt(4) // pad2
        let locationShareInterval = try stream.readInt(8) * 10
        let bssUserIDLower = try stream.readInt(32)
        
        // Name strings
        let pttReleaseIDInfoData = try stream.readBytes(12)
        let pttReleaseIDInfo = String(data: pttReleaseIDInfoData, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? ""
        
        let beaconMessageData = try stream.readBytes(18)
        let beaconMessage = String(data: beaconMessageData, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? ""
        
        let aprsSymbolData = try stream.readBytes(2)
        let aprsSymbol = String(data: aprsSymbolData, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? ""
        
        let aprsCallsignData = try stream.readBytes(6)
        let aprsCallsign = String(data: aprsCallsignData, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? ""
        
        // Check if extended (has upper 32 bits of bss_user_id)
        var bssUserIDUpper = 0
        if stream.remaining >= 32 {
            bssUserIDUpper = try stream.readInt(32)
        }
        
        let bssUserID = (bssUserIDUpper << 32) | bssUserIDLower
        
        return BeaconSettings(
            maxFwdTimes: maxFwdTimes,
            timeToLive: timeToLive,
            pttReleaseSendLocation: pttReleaseSendLocation,
            pttReleaseSendIDInfo: pttReleaseSendIDInfo,
            pttReleaseSendBSSUserID: pttReleaseSendBSSUserID,
            shouldShareLocation: shouldShareLocation,
            sendPwrVoltage: sendPwrVoltage,
            packetFormat: packetFormat,
            allowPositionCheck: allowPositionCheck,
            aprsSSID: aprsSSID,
            locationShareInterval: locationShareInterval,
            bssUserID: bssUserID,
            pttReleaseIDInfo: pttReleaseIDInfo,
            beaconMessage: beaconMessage,
            aprsSymbol: aprsSymbol,
            aprsCallsign: aprsCallsign
        )
    }
    
    // MARK: - Region Decoding
    
    public static func decodeRegionName(_ data: Data) throws -> String {
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? ""
    }
}

/// Protocol message structure
public struct ProtocolMessage {
    public let commandGroup: CommandGroup
    public let isReply: Bool
    public let command: UInt16
    public let body: Data
}
