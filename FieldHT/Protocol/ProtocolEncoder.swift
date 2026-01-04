import Foundation

/// Protocol message encoder - converts Swift models to protocol bytes
public struct ProtocolEncoder {
    
    // MARK: - Message Encoding
    
    public static func encodeMessage(
        commandGroup: CommandGroup,
        command: UInt16,
        isReply: Bool = false,
        body: Data
    ) -> Data {
        var stream = BitStream()
        stream.writeInt(Int(commandGroup.rawValue), bitCount: 16)
        stream.writeBool(isReply)
        stream.writeInt(Int(command), bitCount: 15)
        stream.writeBytes(body)
        return stream.toData()
    }
    
    // MARK: - Device Info Encoding (for GetDevInfo command)
    
    public static func encodeGetDevInfo() -> Data {
        var stream = BitStream()
        stream.writeInt(3, bitCount: 8) // unknown field
        return stream.toData()
    }
    
    // MARK: - Channel Encoding
    
    public static func encodeChannel(_ channel: Channel) -> Data {
        var stream = BitStream()
        
        stream.writeInt(channel.channelID, bitCount: 8)
        stream.writeInt(channel.txMod.toProtocolValue(), bitCount: 2)
        stream.writeInt(Int(channel.txFreq / 1e-6), bitCount: 30)
        stream.writeInt(channel.rxMod.toProtocolValue(), bitCount: 2)
        stream.writeInt(Int(channel.rxFreq / 1e-6), bitCount: 30)
        
        // Sub-audio encoding
        stream.writeInt(encodeSubAudio(channel.txSubAudio), bitCount: 16)
        stream.writeInt(encodeSubAudio(channel.rxSubAudio), bitCount: 16)
        
        stream.writeBool(channel.scan)
        stream.writeBool(channel.txAtMaxPower)
        stream.writeBool(channel.talkAround)
        stream.writeInt(channel.bandwidth.toProtocolValue(), bitCount: 1)
        stream.writeBool(channel.preDeEmphBypass)
        stream.writeBool(channel.sign)
        stream.writeBool(channel.txAtMedPower)
        stream.writeBool(channel.txDisable)
        stream.writeBool(channel.fixedFreq)
        stream.writeBool(channel.fixedBandwidth)
        stream.writeBool(channel.fixedTxPower)
        stream.writeBool(channel.mute)
        stream.writeInt(0, bitCount: 4) // pad
        
        // Name (10 bytes, null-padded)
        var nameData = channel.name.data(using: .utf8) ?? Data()
        if nameData.count > 10 {
            nameData = nameData.prefix(10)
        }
        while nameData.count < 10 {
            nameData.append(0)
        }
        stream.writeBytes(nameData)
        
        return stream.toData()
    }
    
    private static func encodeSubAudio(_ subAudio: SubAudio?) -> Int {
        guard let subAudio = subAudio else { return 0 }
        switch subAudio {
        case .dcs(let dcs):
            return dcs.n
        case .frequency(let freq):
            return Int(freq * 100)
        }
    }
    
    // MARK: - Settings Encoding
    
    public static func encodeSettings(_ settings: Settings) -> Data {
        var stream = BitStream()
        
        let channelALower = settings.channelA & 0x0F
        let channelAUpper = (settings.channelA >> 4) & 0x0F
        let channelBLower = settings.channelB & 0x0F
        let channelBUpper = (settings.channelB >> 4) & 0x0F
        
        stream.writeInt(channelALower, bitCount: 4)
        stream.writeInt(channelBLower, bitCount: 4)
        stream.writeBool(settings.scan)
        stream.writeInt(settings.aghfpCallMode, bitCount: 1)
        stream.writeInt(settings.doubleChannel, bitCount: 2)
        stream.writeInt(settings.squelchLevel, bitCount: 4)
        stream.writeBool(settings.tailElim)
        stream.writeBool(settings.autoRelayEn)
        stream.writeBool(settings.autoPowerOn)
        stream.writeBool(settings.keepAghfpLink)
        stream.writeInt(settings.micGain, bitCount: 3)
        stream.writeInt(settings.txHoldTime, bitCount: 4)
        stream.writeInt(settings.txTimeLimit, bitCount: 5)
        stream.writeInt(settings.localSpeaker, bitCount: 2)
        stream.writeInt(settings.btMicGain, bitCount: 3)
        stream.writeBool(settings.adaptiveResponse)
        stream.writeBool(settings.disTone)
        stream.writeBool(settings.powerSavingMode)
        if settings.autoPowerOff > 7 {
            print("[PROTOCOL-WARN] AutoPowerOff value \(settings.autoPowerOff) exceeds 3 bits (max 7). Truncating.")
        }
        stream.writeInt(settings.autoPowerOff, bitCount: 3)
        
        // auto_share_loc_ch (mapped)
        let autoShareLocChRaw = settings.autoShareLocCh.map { $0 + 1 } ?? 0
        stream.writeInt(autoShareLocChRaw, bitCount: 5)
        
        stream.writeInt(settings.hmSpeaker, bitCount: 2)
        stream.writeInt(settings.positioningSystem, bitCount: 4)
        stream.writeInt(settings.timeOffset, bitCount: 6)
        stream.writeBool(settings.useFreqRange2)
        stream.writeBool(settings.pttLock)
        stream.writeBool(settings.leadingSyncBitEn)
        stream.writeBool(settings.pairingAtPowerOn)
        if settings.screenTimeout > 31 {
            print("[PROTOCOL-WARN] ScreenTimeout value \(settings.screenTimeout) exceeds 5 bits (max 31). Truncating.")
        }
        stream.writeInt(settings.screenTimeout, bitCount: 5)
        stream.writeInt(settings.vfoX, bitCount: 2)
        stream.writeBool(settings.imperialUnit)
        stream.writeInt(channelAUpper, bitCount: 4)
        stream.writeInt(channelBUpper, bitCount: 4)
        stream.writeInt(settings.wxMode, bitCount: 2)
        stream.writeInt(settings.noaaCh, bitCount: 4)
        stream.writeInt(settings.vfo1TxPowerX, bitCount: 2)
        stream.writeInt(settings.vfo2TxPowerX, bitCount: 2)
        stream.writeBool(settings.disDigitalMute)
        stream.writeBool(settings.signalingEccEn)
        stream.writeBool(settings.chDataLock)
        stream.writeInt(0, bitCount: 3) // pad
        stream.writeInt(settings.vfo1ModFreqX, bitCount: 32)
        stream.writeInt(settings.vfo2ModFreqX, bitCount: 32)
        stream.writeInt(settings.reservedExt1, bitCount: 16)
        
        return stream.toData()
    }
    
    // MARK: - Power Status Request Encoding
    
    public static func encodeReadPowerStatus(_ statusType: ProtocolDecoder.PowerStatusType) -> Data {
        var stream = BitStream()
        stream.writeInt(statusType.rawValue, bitCount: 16)
        return stream.toData()
    }
    
    // MARK: - Channel Read Request Encoding
    
    public static func encodeReadChannel(_ channelID: Int) -> Data {
        var stream = BitStream()
        stream.writeInt(channelID, bitCount: 8)
        return stream.toData()
    }
    
    // MARK: - TNC Data Fragment Encoding
    
    public static func encodeTncDataFragment(_ fragment: TncDataFragment) -> Data {
        var stream = BitStream()
        
        stream.writeBool(fragment.isFinalFragment)
        stream.writeBool(fragment.channelID != nil)
        stream.writeInt(fragment.fragmentID, bitCount: 6)
        stream.writeBytes(fragment.data)
        
        if let channelID = fragment.channelID {
            stream.writeInt(channelID, bitCount: 8)
        }
        
        return stream.toData()
    }
    
    // MARK: - Beacon Settings Encoding
    
    public static func encodeBeaconSettings(_ settings: BeaconSettings) -> Data {
        var stream = BitStream()
        
        stream.writeInt(settings.maxFwdTimes, bitCount: 4)
        stream.writeInt(settings.timeToLive, bitCount: 4)
        stream.writeBool(settings.pttReleaseSendLocation)
        stream.writeBool(settings.pttReleaseSendIDInfo)
        stream.writeBool(settings.pttReleaseSendBSSUserID)
        stream.writeBool(settings.shouldShareLocation)
        stream.writeBool(settings.sendPwrVoltage)
        //stream.writeInt(settings.packetFormat.rawValue, bitCount: 1)
        stream.writeBool(settings.allowPositionCheck)
        stream.writeInt(0, bitCount: 1) // pad
        stream.writeInt(settings.aprsSSID, bitCount: 4)
        stream.writeInt(0, bitCount: 4) // pad2
        stream.writeInt(settings.locationShareInterval / 10, bitCount: 8)
        
        let bssUserIDLower = settings.bssUserID & 0xFFFFFFFF
        stream.writeInt(bssUserIDLower, bitCount: 32)
        
        // Name strings (null-padded)
        var pttReleaseIDInfoData = settings.pttReleaseIDInfo.data(using: .utf8) ?? Data()
        if pttReleaseIDInfoData.count > 12 {
            pttReleaseIDInfoData = pttReleaseIDInfoData.prefix(12)
        }
        while pttReleaseIDInfoData.count < 12 {
            pttReleaseIDInfoData.append(0)
        }
        stream.writeBytes(pttReleaseIDInfoData)
        
        var beaconMessageData = settings.beaconMessage.data(using: .utf8) ?? Data()
        if beaconMessageData.count > 18 {
            beaconMessageData = beaconMessageData.prefix(18)
        }
        while beaconMessageData.count < 18 {
            beaconMessageData.append(0)
        }
        stream.writeBytes(beaconMessageData)
        
        var aprsSymbolData = settings.aprsSymbol.data(using: .utf8) ?? Data()
        if aprsSymbolData.count > 2 {
            aprsSymbolData = aprsSymbolData.prefix(2)
        }
        while aprsSymbolData.count < 2 {
            aprsSymbolData.append(0)
        }
        stream.writeBytes(aprsSymbolData)
        
        var aprsCallsignData = settings.aprsCallsign.data(using: .utf8) ?? Data()
        if aprsCallsignData.count > 6 {
            aprsCallsignData = aprsCallsignData.prefix(6)
        }
        while aprsCallsignData.count < 6 {
            aprsCallsignData.append(0)
        }
        stream.writeBytes(aprsCallsignData)
        
        // Extended: upper 32 bits of bss_user_id
        let bssUserIDUpper = (settings.bssUserID >> 32) & 0xFFFFFFFF
        stream.writeInt(bssUserIDUpper, bitCount: 32)
        
        return stream.toData()
    }
    
    // MARK: - Region Encoding
    
    public static func encodeReadRegionName(_ regionID: Int) -> Data {
        var stream = BitStream()
        stream.writeInt(regionID, bitCount: 8)
        return stream.toData()
    }
    
    public static func encodeWriteRegionName(regionID: Int, name: String) -> Data {
        var stream = BitStream()
        stream.writeInt(regionID, bitCount: 8)
        
        // Name (16 bytes? assuming slightly longer than channel name or same)
        // Let's assume 12 bytes to be safe, or just variable. 
        // Based on channel name being 10, let's try 16.
        var nameData = name.data(using: .utf8) ?? Data()
        if nameData.count > 16 {
            nameData = nameData.prefix(16)
        }
        while nameData.count < 16 {
            nameData.append(0)
        }
        stream.writeBytes(nameData)
        return stream.toData()
    }
    
    public static func encodeSetRegion(_ regionID: Int) -> Data {
        var stream = BitStream()
        stream.writeInt(regionID, bitCount: 8)
        return stream.toData()
    }
    
    public static func encodeWriteRegionChannel(regionID: Int, channelID: Int) -> Data {
        var stream = BitStream()
        stream.writeInt(regionID, bitCount: 8)
        stream.writeInt(channelID, bitCount: 8)
        return stream.toData()
    }

    // MARK: - Event Registration Encoding
    
    public static func encodeRegisterNotification(_ eventType: EventType) -> Data {
        var stream = BitStream()
        stream.writeInt(Int(eventType.rawValue), bitCount: 8)
        return stream.toData()
    }
}

