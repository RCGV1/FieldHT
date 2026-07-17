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
    
    // MARK: - Programmable Function Encoding
    
    public static func encodeDoProgFunc(_ effect: Int) -> Data {
        var stream = BitStream()
        stream.writeInt(effect, bitCount: 8)
        return stream.toData()
    }
    
    // MARK: - Channel Encoding
    
    public static func encodeChannel(_ channel: Channel) -> Data {
        var stream = BitStream()
        
        stream.writeInt(channel.channelID, bitCount: 8)
        stream.writeInt(channel.txMod.toProtocolValue(), bitCount: 2)
        stream.writeInt(clampUInt30(Int((channel.txFreq * 1_000_000.0).rounded())), bitCount: 30)
        stream.writeInt(channel.rxMod.toProtocolValue(), bitCount: 2)
        stream.writeInt(clampUInt30(Int((channel.rxFreq * 1_000_000.0).rounded())), bitCount: 30)
        
        // Sub-audio encoding
        stream.writeInt(Int(encodeSubAudioValue(channel.txSubAudio)), bitCount: 16)
        stream.writeInt(Int(encodeSubAudioValue(channel.rxSubAudio)), bitCount: 16)
        
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
    
    public static func encodeSubAudioValue(_ subAudio: SubAudio?) -> UInt16 {
        guard let subAudio else { return 0 }
        switch subAudio {
        case .dcs(let dcs):
            return UInt16(clampUInt16Int(dcs.n))
        case .frequency(let freq):
            return UInt16(clampUInt16Int(Int((freq * 100.0).rounded())))
        }
    }

    // MARK: - APRS Path Encoding

    /// Matches the official programmer's repeater-path normalization before SET_APRS_PATH.
    public static func encodeAPRSPath(_ path: String) -> Data {
        Data(normalizedAPRSPath(path).utf8)
    }

    private static func normalizedAPRSPath(_ path: String) -> String {
        let allowedCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789,-")
        let cleaned = String(path.filter { allowedCharacters.contains($0) })

        return cleaned
            .split(separator: ",", omittingEmptySubsequences: true)
            .prefix(8)
            .compactMap { rawPart in
                let part = String(rawPart)
                guard let hyphen = part.firstIndex(of: "-") else {
                    return part.isEmpty ? nil : part
                }

                let callsign = String(part[..<hyphen])
                guard !callsign.isEmpty else { return nil }

                var ssidText = String(part[part.index(after: hyphen)...].prefix(2))
                if ssidText.count > 1, !ssidText.dropFirst().allSatisfy(\.isNumber) {
                    ssidText = String(ssidText.prefix(1))
                }
                let ssid = min(Int(ssidText) ?? 0, 8)
                return ssid > 0 ? "\(callsign)-\(ssid)" : callsign
            }
            .joined(separator: ",")
    }

    private static func clampUInt30(_ value: Int) -> Int {
        if value <= 0 { return 0 }
        let max = (1 << 30) - 1
        if value >= max { return max }
        return value
    }

    private static func clampUInt16Int(_ value: Int) -> Int {
        if value <= 0 { return 0 }
        if value >= 0xFFFF { return 0xFFFF }
        return value
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
        
        // auto_share_loc_ch is split between this low field and a later three-bit extension.
        let autoShareLocChRaw = settings.autoShareLocCh.map { min(max($0, 0), 254) + 1 } ?? 0
        stream.writeInt(autoShareLocChRaw & 0x1F, bitCount: 5)
        
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
        stream.writeInt((autoShareLocChRaw >> 5) & 0x07, bitCount: 3)
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

    // MARK: - Radio Control Encoding

    public static func encodeSetHTOnOff(_ isOn: Bool) -> Data {
        var stream = BitStream()
        stream.writeBool(isOn)
        return stream.toData()
    }

    public static func encodeRadioSetMode(_ mode: Int) -> Data {
        var stream = BitStream()
        stream.writeInt(mode, bitCount: 8)
        return stream.toData()
    }

    public static func encodeSetIsDigitalSignal(_ isEnabled: Bool) -> Data {
        Data([isEnabled ? 1 : 0])
    }

    public static func encodeSetTime(_ date: Date) -> Data {
        var stream = BitStream()
        let unixTime = max(0, Int(date.timeIntervalSince1970.rounded()))
        stream.writeInt(unixTime, bitCount: 32)
        return stream.toData()
    }

    // MARK: - Frequency/Satellite Mode

    /// Encodes `freqModeSetPar` (basic cmd 35).
    ///
    /// The stock BTECH app packs this bitfield for both frequency scanning and
    /// satellite mode. In particular, the `mode` nibble must be explicit: the
    /// former 0x0A00 constant selected satellite mode for every caller.
    public static func encodeFreqModeSetPar(
        rxFreqHzX: UInt32,
        txFreqHzX: UInt32,
        rxSubAudio: SubAudio? = nil,
        txSubAudio: SubAudio? = nil,
        mode: FrequencyMode,
        step: FrequencyScanStep = .fiveKHz,
        extendedParameter: UInt16 = 0
    ) -> Data {
        var stream = BitStream()
        stream.writeInt(0, bitCount: 2) // FM modulation
        stream.writeInt(clampUInt30(Int(rxFreqHzX)), bitCount: 30)
        stream.writeInt(0, bitCount: 2) // FM modulation
        stream.writeInt(clampUInt30(Int(txFreqHzX)), bitCount: 30)
        stream.writeInt(Int(encodeSubAudioValue(rxSubAudio)), bitCount: 16)
        stream.writeInt(Int(encodeSubAudioValue(txSubAudio)), bitCount: 16)
        stream.writeBool(false) // low TX power
        stream.writeInt(step.rawValue, bitCount: 3)
        stream.writeInt(mode.rawValue, bitCount: 4)
        stream.writeInt(0, bitCount: 6) // reserved
        stream.writeInt(0, bitCount: 2) // frequency-difference mode: no change
        stream.writeInt(Int(extendedParameter), bitCount: 16)
        return stream.toData()
    }

    /// Encodes a satellite info payload (basic cmd 77) as seen in BLE logs.
    /// Layout (big-endian):
    /// - 20-byte name (UTF-8, null padded)
    /// - UInt16 rangeKmX10
    /// - UInt16 azDegX10
    /// - Int16 dopplerShiftHz
    /// - UInt16 elDegX10
    /// - UInt16 altKmX10
    public static func encodeSatModeSetInfo(
        name: String,
        rangeKm: Double,
        dopplerShiftHz: Int,
        azimuthDeg: Double,
        elevationDeg: Double,
        altitudeKm: Double
    ) -> Data {
        var data = Data()
        data.appendFixedLengthUTF8(name, length: 20)

        let rangeX10 = clampUInt16(Int((rangeKm * 10.0).rounded()))
        let azX10 = clampUInt16(Int((azimuthDeg * 10.0).rounded()))
        let doppler = clampInt16(dopplerShiftHz)
        let elX10 = clampUInt16(Int((elevationDeg * 10.0).rounded()))
        let altX10 = clampUInt16(Int((altitudeKm * 10.0).rounded()))

        data.appendUInt16BE(rangeX10)
        data.appendUInt16BE(azX10)
        data.appendInt16BE(doppler)
        data.appendUInt16BE(elX10)
        data.appendUInt16BE(altX10)
        return data
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

    // MARK: - Volume Encoding

    /// Encode volume level (radio expects 0-255, iOS uses 0-100)
    public static func encodeSetVolume(_ level: Int) -> Data {
        var stream = BitStream()
        // Convert 0-100 iOS volume to 0-255 radio volume
        let radioLevel = (max(0, min(100, level)) * 255) / 100
        stream.writeInt(radioLevel, bitCount: 8)
        return stream.toData()
    }

    // MARK: - Beacon Settings Encoding
    
    public static func encodeBeaconSettings(_ settings: BeaconSettings) -> Data {
        let canonicalPayload = encodeCanonicalBeaconSettings(settings)
        guard let rawPayload = settings.rawProtocolPayload, rawPayload.count >= 50 else {
            return canonicalPayload
        }

        return mergeBeaconSettings(
            canonicalPayload,
            preservingUnknownBitsFrom: rawPayload
        )
    }

    private static func encodeCanonicalBeaconSettings(_ settings: BeaconSettings) -> Data {
        var stream = BitStream()
        
        stream.writeInt(settings.maxFwdTimes, bitCount: 4)
        stream.writeInt(settings.timeToLive, bitCount: 4)
        stream.writeBool(settings.pttReleaseSendLocation)
        stream.writeBool(settings.pttReleaseSendIDInfo)
        stream.writeBool(settings.pttReleaseSendBSSUserID)
        stream.writeBool(settings.shouldShareLocation)
        stream.writeBool(settings.sendPwrVoltage)
        stream.writeInt(settings.packetFormat.toProtocolValue(), bitCount: 1)
        stream.writeBool(settings.allowPositionCheck)
        stream.writeInt(0, bitCount: 1) // pad
        stream.writeInt(settings.aprsSSID, bitCount: 4)
        stream.writeBool(settings.smartBeaconEnabled)
        stream.writeBool(settings.micEEnabled)
        stream.writeBool(settings.sendIDByAPRS)
        stream.writeInt(0, bitCount: 1) // reserved
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

        if let smartBeaconMinimumInterval = settings.smartBeaconMinimumInterval,
           let smartBeaconMaximumInterval = settings.smartBeaconMaximumInterval {
            stream.writeInt(smartBeaconMinimumInterval, bitCount: 4)
            stream.writeInt(smartBeaconMaximumInterval, bitCount: 5)
            stream.writeInt(0, bitCount: 7) // reserved
        }
        
        return stream.toData()
    }

    /// BSS payloads grow across firmware revisions. Preserve the radio's
    /// unmodeled padding, reserved fields, and any trailing extension bytes.
    private static func mergeBeaconSettings(
        _ canonicalPayload: Data,
        preservingUnknownBitsFrom rawPayload: Data
    ) -> Data {
        var canonicalStream = BitStream(data: canonicalPayload)
        guard let canonicalBits = try? canonicalStream.readBits(canonicalPayload.count * 8) else {
            return canonicalPayload
        }

        var mergedStream = BitStream(data: rawPayload)
        let baseKnownRanges = [0..<15, 16..<23, 24..<400]
        for range in baseKnownRanges {
            guard range.upperBound <= canonicalBits.count,
                  mergedStream.replaceBits(Array(canonicalBits[range]), at: range.lowerBound) else {
                return canonicalPayload
            }
        }

        // The final seven bits of the 52-byte layout remain reserved.
        if canonicalPayload.count >= 52, rawPayload.count >= 52 {
            guard mergedStream.replaceBits(Array(canonicalBits[400..<409]), at: 400) else {
                return canonicalPayload
            }
        }

        return mergedStream.toData()
    }
    
    // MARK: - Region Encoding
    
    public static func encodeReadRegionName(_ regionID: Int) -> Data {
        var stream = BitStream()
        stream.writeInt(regionID, bitCount: 8)
        return stream.toData()
    }
    
    public static func encodeWriteRegionName(regionID: Int, name: String) -> Data {
        var stream = BitStream()
        // NOTE: UV-PRO firmware reply for readRegionName returns 10 name bytes.
        // writeRegionName appears to accept a 10-byte name; some firmware also expects the
        // regionID as the first byte (mirrors writeRegionCh / readRegionName conventions).
        stream.writeInt(regionID, bitCount: 8)
        var nameData = name.data(using: .utf8) ?? Data()
        if nameData.count > 10 {
            nameData = nameData.prefix(10)
        }
        while nameData.count < 10 {
            nameData.append(0)
        }
        stream.writeBytes(nameData)
        return stream.toData()
    }

    public static func encodeWriteRegionNameNameOnly(_ name: String) -> Data {
        var stream = BitStream()
        var nameData = name.data(using: .utf8) ?? Data()
        if nameData.count > 10 {
            nameData = nameData.prefix(10)
        }
        while nameData.count < 10 {
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

    /// The stock programmer writes one complete channel payload after the
    /// region and zero-based memory-slot bytes.
    public static func encodeWriteRegionChannel(regionID: Int, slot: Int, channel: Channel) -> Data {
        var body = Data([UInt8(clamping: regionID), UInt8(clamping: slot)])
        body.append(encodeChannel(channel).dropFirst())
        return body
    }

    // MARK: - Event Registration Encoding
    
    public static func encodeRegisterNotification(_ eventType: EventType) -> Data {
        var stream = BitStream()
        stream.writeInt(Int(eventType.rawValue), bitCount: 8)
        return stream.toData()
    }
    
    // MARK: - PF Encoding
    
    public static func encodeGetPF() -> Data {
        // GetPFBody is empty
        return Data()
    }
    
    public static func encodeSetPF(_ pfConfig: PFConfig) -> Data {
        var stream = BitStream()

        // UV-PRO firmware expects `setPF` as an effect-only table.
        // The table order is device-defined and matches the order returned by `getPF`.
        // Each entry is one byte: PFEffectType.
        for pf in pfConfig.pf {
            stream.writeInt(pf.effect.rawValue, bitCount: 8)
        }
        
        return stream.toData()
    }

    // MARK: - Private helpers

    private static func clampUInt16(_ value: Int) -> UInt16 {
        if value <= 0 { return 0 }
        if value >= 0xFFFF { return 0xFFFF }
        return UInt16(value)
    }

    private static func clampInt16(_ value: Int) -> Int16 {
        if value <= Int(Int16.min) { return Int16.min }
        if value >= Int(Int16.max) { return Int16.max }
        return Int16(value)
    }
}

private extension Data {
    mutating func appendUInt16BE(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendInt16BE(_ value: Int16) {
        let u = UInt16(bitPattern: value)
        appendUInt16BE(u)
    }

    mutating func appendFixedLengthUTF8(_ string: String, length: Int) {
        var d = string.data(using: .utf8) ?? Data()
        if d.count > length {
            d = d.prefix(length)
        }
        while d.count < length {
            d.append(0)
        }
        append(d)
    }
}
