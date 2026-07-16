import Foundation

/// Event handler type
public typealias EventHandler = (EventMessage) -> Void

/// Command connection - low-level interface for communicating with the radio
public class CommandConnection: BLEConnectionDelegate {
    private struct PendingReply {
        let id: UUID
        let continuation: CheckedContinuation<RadioMessage, Error>
    }

    private let bleConnection: BLEConnection
    private var eventHandlers: [UUID: EventHandler] = [:]
    private var pendingReplies: [UInt16: PendingReply] = [:]
    private let replySequencer = AsyncSemaphore(value: 1)
    private let queue = DispatchQueue(label: "com.benlink.command")

    private func commandLabel(commandGroup: CommandGroup, command: UInt16) -> String {
        switch commandGroup {
        case .basic:
            if let basic = BasicCommand(rawValue: command) {
                return "basic.\(basic)"
            }
            return "basic.unknown(\(command))"
        case .extended:
            return "extended(\(command))"
        }
    }

    private func hexString(_ data: Data) -> String {
        data.map { String(format: "%02hhx", $0) }.joined()
    }

    private func logUnknownPacket(prefix: String, message: ProtocolMessage) {
        let label = commandLabel(commandGroup: message.commandGroup, command: message.command)
        print("\(prefix) label=\(label) reply=\(message.isReply) body=\(hexString(message.body))")
        guard BLECaptureStore.isEnabled else { return }
        Task {
            await BLECaptureStore.shared.recordNote(category: "unknown_packet", message: prefix, fields: [
                "label": label,
                "reply": String(message.isReply),
                "body": hexString(message.body)
            ])
        }
    }

    private func logDecodedOpaqueReply(message: ProtocolMessage, description: String, fields: [String: String]) {
        let label = commandLabel(commandGroup: message.commandGroup, command: message.command)
        print("[BLE-ACK] label=\(label) \(description)")
        guard BLECaptureStore.isEnabled else { return }
        Task {
            await BLECaptureStore.shared.recordNote(category: "decoded_ack", message: description, fields: fields.merging([
                "label": label,
                "reply": String(message.isReply),
                "body": hexString(message.body)
            ]) { current, _ in current })
        }
    }
    
    /// Connection state - true when fully connected and ready to communicate
    public var isConnected: Bool {
        return bleConnection.isConnected
    }
    

    
    private init(bleConnection: BLEConnection) {
        self.bleConnection = bleConnection
        self.bleConnection.delegate = self
    }
    
    /// Create a new BLE command connection
    /// - Note: Connection is created but not yet connected. Call connect(to:) to establish connection.
    public static func newBLE(
        deviceUUID: UUID,
        radioManager: RadioManager? = nil,
        enableStateRestoration: Bool = true
    ) -> CommandConnection {
        let ble = BLEConnection(
            deviceUUID: deviceUUID,
            radioManager: radioManager,
            enableStateRestoration: enableStateRestoration
        )
        return CommandConnection(bleConnection: ble)
    }
    
    /// Connect to a specific radio device by UUID
    /// - Parameter deviceUUID: The UUID of the device to connect to (typically from BLEScanner)
    /// - Throws: BLEError if connection fails or bluetooth is unavailable
    public func connect() async throws {
        try await bleConnection.connect()
        print("CommandConnection: Successfully connected")
    }
    
    /// Disconnect from the radio
    /// - Note: After disconnecting, you can reconnect to the same or different device using connect(to:)
    public func disconnect() async {
        print("CommandConnection: Disconnecting from device")
        
        // Clear any pending operations before disconnecting
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Cancel all pending replies
            for (_, pendingReply) in self.pendingReplies {
                pendingReply.continuation.resume(throwing: BLEError.notConnected)
            }
            self.pendingReplies.removeAll()
        }
        
        await bleConnection.disconnect()
        print("CommandConnection: Disconnected")
    }
    
    /// Send raw bytes (for debugging)
    public func sendBytes(_ data: Data) async throws {
        try bleConnection.send(data)
    }
    
    /// Add an event handler
    @discardableResult
    public func addEventHandler(_ handler: @escaping EventHandler) -> () -> Void {
        let id = UUID()
        queue.async {
            self.eventHandlers[id] = handler
        }
        return {
            self.queue.async {
                self.eventHandlers.removeValue(forKey: id)
            }
        }
    }
    
    // MARK: - BLEConnectionDelegate
    
    public func connectionDidConnect(_ connection: BLEConnection) {
        // Connection established
    }
    
    public func connectionDidDisconnect(_ connection: BLEConnection, error: Error?) {
        // Handle disconnection
        queue.async {
            for (_, pendingReply) in self.pendingReplies {
                pendingReply.continuation.resume(throwing: BLEError.notConnected)
            }
            self.pendingReplies.removeAll()
        }
    }
    
    public func connection(_ connection: BLEConnection, didReceiveData data: Data) {
        let hex = hexString(data)
        print("[BLE-RX] Raw (\(data.count) bytes): \(hex)")

        queue.async {
            self.handleReceivedData(data, hex: hex)
        }
    }

    private func handleReceivedData(_ data: Data, hex: String) {
        do {
            let message = try ProtocolDecoder.decodeMessage(data)
            let label = commandLabel(commandGroup: message.commandGroup, command: message.command)
            print("[BLE-RX] Decoded -> Reply: \(message.isReply), \(label), Body: \(message.body.map { String(format: "%02hhx", $0) }.joined())")
            if BLECaptureStore.isEnabled {
                Task {
                    await BLECaptureStore.shared.recordNote(category: "protocol_message", message: "Decoded protocol message", fields: [
                        "label": label,
                        "reply": String(message.isReply),
                        "body": self.hexString(message.body)
                    ])
                }
            }

            if message.isReply {
                if let pendingReply = pendingReplies[message.command] {
                    pendingReplies.removeValue(forKey: message.command)

                    let reply = try decodeReply(message: message)
                    pendingReply.continuation.resume(returning: .reply(reply))
                } else {
                    if handleUnsolicitedReply(message) {
                        return
                    }
                    let isQuietBasicReply = (message.commandGroup == .basic) && (
                        message.command == BasicCommand.freqModeSetPar.rawValue ||
                        message.command == BasicCommand.freqModeGetStatus.rawValue ||
                        message.command == BasicCommand.satModeSetInfo.rawValue ||
                        message.command == BasicCommand.writeBSSSettings.rawValue ||
                        message.command == BasicCommand.setVolume.rawValue ||
                        message.command == BasicCommand.setTime.rawValue
                    )
                    if !isQuietBasicReply {
                        logUnknownPacket(prefix: "[BLE-UNKNOWN-REPLY]", message: message)
                    }
                }
            } else if message.commandGroup == .basic && message.command == BasicCommand.eventNotification.rawValue {
                print("[EVENT] Received event notification, body: \(message.body.map { String(format: "%02hhx", $0) }.joined())")
                let event = try decodeEvent(message: message)
                print("[EVENT] Decoded event: \(event)")
                for handler in eventHandlers.values {
                    handler(event)
                }
            } else {
                logUnknownPacket(prefix: "[BLE-UNKNOWN-MESSAGE]", message: message)
            }
        } catch {
            let header = data.prefix(4)
            print("[BLE-DECODE-ERR] error=\(error) raw=\(hex) header=\(hexString(header))")
            if BLECaptureStore.isEnabled {
                Task {
                    await BLECaptureStore.shared.recordNote(category: "decode_error", message: "Failed to decode BLE payload", fields: [
                        "error": String(describing: error),
                        "raw": hex,
                        "header": self.hexString(header)
                    ])
                }
            }
        }
    }

    private func handleUnsolicitedReply(_ message: ProtocolMessage) -> Bool {
        do {
            switch (message.commandGroup, message.command) {
            case (.basic, BasicCommand.registerNotification.rawValue):
                if case .registerNotificationAck(let code) = try decodeReply(message: message) {
                    logDecodedOpaqueReply(
                        message: message,
                        description: "registerNotification ack code=\(code)",
                        fields: ["code": String(code)]
                    )
                    return true
                }
            case (.basic, BasicCommand.setTime.rawValue):
                guard let code = message.body.first else {
                    return false
                }
                let description: String
                switch code {
                case ReplyStatus.success.rawValue:
                    description = "setTime final ack"
                case ReplyStatus.invalidParameter.rawValue:
                    description = "setTime provisional ack"
                default:
                    description = "setTime ack code=\(code)"
                }
                logDecodedOpaqueReply(
                    message: message,
                    description: description,
                    fields: ["code": String(code)]
                )
                return true
            default:
                return false
            }
        } catch {
            return false
        }
        return false
    }

    // MARK: - Fire-and-forget commands

    public func setFreqModeParameters(
        rxFreqHzX: UInt32,
        txFreqHzX: UInt32,
        rxSubAudio: SubAudio? = nil,
        txSubAudio: SubAudio? = nil,
        mode: FrequencyMode,
        step: FrequencyScanStep = .fiveKHz,
        extendedParameter: UInt16 = 0
    ) async throws {
        let body = ProtocolEncoder.encodeFreqModeSetPar(
            rxFreqHzX: rxFreqHzX,
            txFreqHzX: txFreqHzX,
            rxSubAudio: rxSubAudio,
            txSubAudio: txSubAudio,
            mode: mode,
            step: step,
            extendedParameter: extendedParameter
        )
        let data = ProtocolEncoder.encodeMessage(
            commandGroup: .basic,
            command: BasicCommand.freqModeSetPar.rawValue,
            body: body
        )
        try await sendBytes(data)
    }

    public func getFreqModeStatus() async throws -> FrequencyModeStatus {
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.freqModeGetStatus.rawValue,
            body: Data()
        )
        guard case .reply(.frequencyModeStatus(let status)) = reply else {
            throw ProtocolError.invalidReply
        }
        return status
    }

    public func setSatModeInfo(
        name: String,
        rangeKm: Double,
        dopplerShiftHz: Int,
        azimuthDeg: Double,
        elevationDeg: Double,
        altitudeKm: Double
    ) async throws {
        let body = ProtocolEncoder.encodeSatModeSetInfo(
            name: name,
            rangeKm: rangeKm,
            dopplerShiftHz: dopplerShiftHz,
            azimuthDeg: azimuthDeg,
            elevationDeg: elevationDeg,
            altitudeKm: altitudeKm
        )
        let data = ProtocolEncoder.encodeMessage(
            commandGroup: .basic,
            command: BasicCommand.satModeSetInfo.rawValue,
            body: body
        )
        try await sendBytes(data)
    }

    public func syncTime(_ date: Date = Date()) async throws {
        let body = ProtocolEncoder.encodeSetTime(date)
        let data = ProtocolEncoder.encodeMessage(
            commandGroup: .basic,
            command: BasicCommand.setTime.rawValue,
            body: body
        )
        try await sendBytes(data)
    }
    
    // MARK: - Reply Decoding
    
    private func decodeReply(message: ProtocolMessage) throws -> ReplyMessage {
        switch (message.commandGroup, message.command) {
        case (.basic, BasicCommand.freqModeGetStatus.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to get frequency mode status")
            }
            return .frequencyModeStatus(try ProtocolDecoder.decodeFrequencyModeStatus(Data(message.body.dropFirst(1))))

        case (.basic, BasicCommand.freqModeSetPar.rawValue):
            // Reverse-engineered command 35 (freqModeSetPar). Treat reply as ack.
            return .success

        case (.basic, BasicCommand.satModeSetInfo.rawValue):
            // Reverse-engineered command 77 (satModeSetInfo). Treat reply as ack.
            return .success

        case (.basic, BasicCommand.registerNotification.rawValue):
            guard let ackCode = message.body.first else {
                throw ProtocolError.invalidReply
            }
            // The radio returns a one-byte opaque ack here. We don't know the
            // exact semantics yet, but it is a stable, recognized reply shape.
            return .registerNotificationAck(ackCode)

        case (.basic, BasicCommand.getDevInfo.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to get device info")
            }
            let bodyData = message.body.dropFirst(1) // Skip reply_status byte
            let deviceInfo = try ProtocolDecoder.decodeDeviceInfo(bodyData)
            print("[BLE-RX] Decoded DeviceInfo: \(deviceInfo)")
            return .deviceInfo(deviceInfo)
            
        case (.basic, BasicCommand.readRFCh.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to get channel")
            }
            let bodyData = message.body.dropFirst(1) // Skip reply_status byte
            let channel = try ProtocolDecoder.decodeChannel(bodyData)
            print("[BLE-RX] Decoded Channel: \(channel)")
            return .channel(channel)
            
        case (.basic, BasicCommand.writeRFCh.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to set channel")
            }
            return .success
            
        case (.basic, BasicCommand.readSettings.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to get settings")
            }
            let bodyData = message.body.dropFirst(1) // Skip reply_status byte
            let settings = try ProtocolDecoder.decodeSettings(bodyData)
            print("[BLE-RX] Decoded Settings: \(settings)")
            return .settings(settings)
            
        case (.basic, BasicCommand.writeSettings.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to set settings")
            }
            return .success

        case (.basic, BasicCommand.setHTOnOff.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to set HT on/off")
            }
            return .success

        case (.basic, BasicCommand.radioSetMode.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to set radio mode")
            }
            return .success
            
        case (.basic, BasicCommand.getHTStatus.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to get status")
            }
            let bodyData = message.body.dropFirst(1) // Skip reply_status byte
            let status = try ProtocolDecoder.decodeStatus(bodyData)
            return .status(status)
            
        case (.basic, BasicCommand.readStatus.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to read power status")
            }
            let bodyData = message.body.dropFirst(1) // Skip reply_status byte
            let (type, value) = try ProtocolDecoder.decodePowerStatus(bodyData)
            
            switch type {
            case .batteryVoltage:
                guard let v = value as? Double else {
                    throw ProtocolError.decodeError("Expected Double for batteryVoltage")
                }
                return .batteryVoltage(v)
            case .batteryLevel:
                guard let v = value as? Int else {
                    throw ProtocolError.decodeError("Expected Int for batteryLevel")
                }
                return .batteryLevel(v)
            case .batteryLevelAsPercentage:
                guard let v = value as? Int else {
                    throw ProtocolError.decodeError("Expected Int for batteryLevelAsPercentage")
                }
                return .batteryLevelAsPercentage(v)
            case .rcBatteryLevel:
                guard let v = value as? Int else {
                    throw ProtocolError.decodeError("Expected Int for rcBatteryLevel")
                }
                return .rcBatteryLevel(v)
            case .unknown:
                return .error(.invalidParameter, "Unknown power status type")
            }
            
        case (.basic, BasicCommand.getPosition.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to get position")
            }
            let bodyData = message.body.dropFirst(1) // Skip reply_status byte
            let position = try ProtocolDecoder.decodePosition(bodyData)
            return .position(position)
            
        case (.basic, BasicCommand.readBSSSettings.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to get beacon settings")
            }
            let bodyData = message.body.dropFirst(1) // Skip reply_status byte
            let beaconSettings = try ProtocolDecoder.decodeBeaconSettings(bodyData)
            return .beaconSettings(beaconSettings)
            
        case (.basic, BasicCommand.writeBSSSettings.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to set beacon settings")
            }
            return .success

        case (.basic, BasicCommand.getAPRSPath.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to get APRS path")
            }
            return .aprsPath(ProtocolDecoder.decodeAPRSPath(Data(message.body.dropFirst(1))))

        case (.basic, BasicCommand.setAPRSPath.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to set APRS path")
            }
            return .success
            
        case (.basic, BasicCommand.htSendData.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to send TNC data")
            }
            return .success
            
        case (.basic, BasicCommand.readRegionName.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to get region name")
            }
            let bodyData = message.body.dropFirst(1)
            // Reply body format: [region_id (1 byte)] + [name bytes]
            if bodyData.isEmpty {
                return .regionName("")
            }
            let nameData = bodyData.dropFirst(1)
            let name = try ProtocolDecoder.decodeRegionName(nameData)
            return .regionName(name)
            
        case (.basic, BasicCommand.writeRegionName.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to set region name")
            }
            return .success
            
        case (.basic, BasicCommand.setRegion.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to set region")
            }
            return .success
            
        case (.basic, BasicCommand.writeRegionCh.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to set region channel")
            }
            return .success
            
        case (.basic, BasicCommand.getPF.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to get PF")
            }
            let bodyData = message.body
            let pfConfig = try ProtocolDecoder.decodePF(bodyData)
            return .pf(pfConfig)
            
        case (.basic, BasicCommand.setPF.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to set PF")
            }
            return .success

        case (.basic, BasicCommand.getPFActions.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to get PF actions")
            }
            let bodyData = Data(message.body.dropFirst(1))
            print("[BLE-PF-ACTIONS] raw=\(hexString(bodyData))")
            if BLECaptureStore.isEnabled {
                Task {
                    await BLECaptureStore.shared.recordNote(category: "pf_actions", message: "Decoded PF actions payload", fields: [
                        "body": hexString(bodyData)
                    ])
                }
            }
            return .pfActions(bodyData)

        case (.basic, BasicCommand.getVolume.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to get volume")
            }
            let bodyData = message.body.dropFirst(1)
            guard let firstByte = bodyData.first else {
                print("[BLE-WARN] Volume response empty after status byte")
                return .volume(0)
            }
            // Radio returns 0-255, convert to 0-100 for iOS
            let radioVolume = Int(firstByte)
            let iosVolume = (radioVolume * 100) / 255
            print("[BLE-RX] Volume: radio=\(radioVolume), ios=\(iosVolume)")
            return .volume(iosVolume)

        case (.basic, BasicCommand.setVolume.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to set volume")
            }
            return .success

        default:
            logUnknownPacket(prefix: "[BLE-UNKNOWN-REPLY-TYPE]", message: message)
            return .error(.notSupported, "Unknown reply type")
        }
    }
    
    private func decodeReplyStatus(_ data: Data) throws -> ReplyStatus {
        guard !data.isEmpty else {
            print("[BLE-ERR] Empty reply data")
            throw ProtocolError.decodeError("Empty reply data")
        }
        guard let status = ReplyStatus(rawValue: data[0]) else {
            print("[BLE-ERR] Invalid reply status byte: \(data[0])")
            throw ProtocolError.decodeError("Invalid reply status")
        }
        if status != .success {
            print("[BLE-STATUS] Reply Status: \(status) (0x\(String(format: "%02x", data[0])))")
        }
        return status
    }
    
    // MARK: - Event Decoding
    
    private func decodeEvent(message: ProtocolMessage) throws -> EventMessage {
        var stream = BitStream(data: message.body)
        let eventTypeRaw = try stream.readInt(8)
        guard let eventType = EventType(rawValue: UInt8(eventTypeRaw)) else {
            let rawEventData = Data(message.body.dropFirst())
            print("[BLE-UNKNOWN-EVENT] type=\(eventTypeRaw) body=\(hexString(rawEventData))")
            if BLECaptureStore.isEnabled {
                Task {
                    await BLECaptureStore.shared.recordNote(category: "unknown_event", message: "Unknown event type", fields: [
                        "type": String(eventTypeRaw),
                        "body": hexString(rawEventData)
                    ])
                }
            }
            return .raw(.unknown, rawEventData)
        }
        
        let eventData = try stream.readBytes(stream.remaining / 8)
        
        switch eventType {
        case .htStatusChanged:
            let status = try ProtocolDecoder.decodeStatus(eventData)
            return .statusChanged(status)

        case .radioStatusChanged:
            let status = try ProtocolDecoder.decodeStatus(eventData)
            return .radioStatusChanged(status)
            
        case .htChChanged:
            let channel = try ProtocolDecoder.decodeChannel(eventData)
            return .channelChanged(channel)
            
        case .htSettingsChanged:
            let settings = try ProtocolDecoder.decodeSettings(eventData)
            return .settingsChanged(settings)

        case .bssSettingsChanged:
            let settings = try ProtocolDecoder.decodeBeaconSettings(eventData)
            return .beaconSettingsChanged(settings)

        case .positionChanged:
            let position = try ProtocolDecoder.decodePosition(eventData)
            return .positionChanged(position)
            
        case .dataRxd:
            let fragment = try ProtocolDecoder.decodeTncDataFragment(eventData)
            return .tncDataFragmentReceived(fragment)

        case .dataTxd:
            let fragment = try ProtocolDecoder.decodeTncDataFragment(eventData)
            return .tncDataFragmentTransmitted(fragment)
            
        default:
            print("[BLE-EVENT-RAW] type=\(eventType) body=\(hexString(eventData))")
            if BLECaptureStore.isEnabled {
                Task {
                    await BLECaptureStore.shared.recordNote(category: "raw_event", message: "Known event with undecoded payload", fields: [
                        "type": String(eventType.rawValue),
                        "name": String(describing: eventType),
                        "body": hexString(eventData)
                    ])
                }
            }
            return .raw(eventType, eventData)
        }
    }
    
    // MARK: - Command API
    
    private func sendCommandAndWaitForReply(
        commandGroup: CommandGroup,
        command: UInt16,
        body: Data,
        timeout: TimeInterval = 5.0
    ) async throws -> RadioMessage {
        return try await replySequencer.withPermit {
            let requestID = UUID()
            let hexBody = body.map { String(format: "%02hhx", $0) }.joined()
            print("[BLE-TX] Sending -> Grp: \(commandGroup), Cmd: \(command), Body: \(hexBody)")

            return try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    // If there's already a pending reply for this command, fail it to prevent leaking.
                    if let existing = self.pendingReplies[command] {
                        existing.continuation.resume(throwing: CancellationError())
                    }

                    self.pendingReplies[command] = PendingReply(id: requestID, continuation: continuation)

                    let messageData = ProtocolEncoder.encodeMessage(
                        commandGroup: commandGroup,
                        command: command,
                        isReply: false,
                        body: body
                    )

#if DEBUG
                    let hexMessage = messageData.map { String(format: "%02hhx", $0) }.joined()
                    print("[BLE-TX-RAW] \(hexMessage)")
                    if let parsed = try? ProtocolDecoder.decodeMessage(messageData) {
                        let parsedBodyHex = parsed.body.map { String(format: "%02hhx", $0) }.joined()
                        print("[BLE-TX-PARSED] Grp: \(parsed.commandGroup), isReply: \(parsed.isReply), Cmd: \(parsed.command), Body: \(parsedBodyHex)")
                    } else {
                        print("[BLE-TX-PARSED] Failed to decode outgoing message")
                    }
#endif

                    Task {
                        do {
                            try await self.bleConnection.send(messageData)

                            // Set timeout
                            // We use a separate task for waiting, but must dispatch back to queue to access state.
                            Task {
                                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                                self.queue.async {
                                    guard let pendingReply = self.pendingReplies[command],
                                          pendingReply.id == requestID else {
                                        return
                                    }

                                    print("[BLE-CMD-ERR] Command \(command) timed out waiting for reply")
                                    self.pendingReplies.removeValue(forKey: command)
                                    pendingReply.continuation.resume(throwing: ProtocolError.timeout)
                                }
                            }
                        } catch {
                            print("[BLE-CMD-ERR] Command \(command) failed to send: \(error)")
                            self.queue.async {
                                // Only resume if this request is still pending.
                                guard let pendingReply = self.pendingReplies[command],
                                      pendingReply.id == requestID else {
                                    return
                                }

                                self.pendingReplies.removeValue(forKey: command)
                                pendingReply.continuation.resume(throwing: error)
                            }
                        }
                    }
                }
            }
        }
    }
    
    public func getDeviceInfo() async throws -> DeviceInfo {
        let body = ProtocolEncoder.encodeGetDevInfo()
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.getDevInfo.rawValue,
            body: body
        )
        
        guard case .reply(.deviceInfo(let deviceInfo)) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }
        
        return deviceInfo
    }
    
    public func getChannel(_ channelID: Int) async throws -> Channel {
        let body = ProtocolEncoder.encodeReadChannel(channelID)
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.readRFCh.rawValue,
            body: body
        )
        
        guard case .reply(.channel(let channel)) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }
        
        return channel
    }
    
    public func setChannel(_ channel: Channel) async throws {
        let body = ProtocolEncoder.encodeChannel(channel)
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.writeRFCh.rawValue,
            body: body
        )
        
        guard case .reply(.success) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }
    }
    
    public func getSettings() async throws -> Settings {
        let body = Data()
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.readSettings.rawValue,
            body: body
        )
        
        guard case .reply(.settings(let settings)) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }
        
        return settings
    }
    
    public func setSettings(_ settings: Settings) async throws {
        let body = ProtocolEncoder.encodeSettings(settings)
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.writeSettings.rawValue,
            body: body
        )
        
        guard case .reply(.success) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }
    }
    
    public func setHTOnOff(_ isOn: Bool) async throws {
        let body = ProtocolEncoder.encodeSetHTOnOff(isOn)
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.setHTOnOff.rawValue,
            body: body
        )
        guard case .reply(.success) = reply else {
            throw ProtocolError.invalidReply
        }
    }


    public func setRadioMode(_ mode: Int) async throws {
        let body = ProtocolEncoder.encodeRadioSetMode(mode)
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.radioSetMode.rawValue,
            body: body
        )
        guard case .reply(.success) = reply else {
            throw ProtocolError.invalidReply
        }
    }
    
    public func executePFAction(_ effect: Int) async throws {
        let body = ProtocolEncoder.encodeDoProgFunc(effect)
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.doProgFunc.rawValue,
            body: body
        )
        guard case .reply(.success) = reply else {
            throw ProtocolError.invalidReply
        }
    }
    
    public func getStatus() async throws -> Status {
        let body = Data()
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.getHTStatus.rawValue,
            body: body
        )
        
        guard case .reply(.status(let status)) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }
        
        return status
    }
    
    public func getBatteryVoltage() async throws -> Double {
        let body = ProtocolEncoder.encodeReadPowerStatus(.batteryVoltage)
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.readStatus.rawValue,
            body: body
        )
        
        guard case .reply(.batteryVoltage(let voltage)) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }
        
        return voltage
    }
    
    public func getBatteryLevel() async throws -> Int {
        let body = ProtocolEncoder.encodeReadPowerStatus(.batteryLevel)
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.readStatus.rawValue,
            body: body
        )
        
        guard case .reply(.batteryLevel(let level)) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }
        
        return level
    }
    
    public func getBatteryLevelAsPercentage() async throws -> Int {
        let body = ProtocolEncoder.encodeReadPowerStatus(.batteryLevelAsPercentage)
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.readStatus.rawValue,
            body: body
        )
        
        guard case .reply(.batteryLevelAsPercentage(let percentage)) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }
        
        return percentage
    }
    
    public func getRCBatteryLevel() async throws -> Int {
        let body = ProtocolEncoder.encodeReadPowerStatus(.rcBatteryLevel)
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.readStatus.rawValue,
            body: body
        )

        guard case .reply(.rcBatteryLevel(let level)) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }

        return level
    }
    
    public func getPosition() async throws -> Position {
        let body = Data()
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.getPosition.rawValue,
            body: body
        )
        
        guard case .reply(.position(let position)) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }
        
        return position
    }

    // MARK: - Volume Control

    /// Get the current volume level (0-100)
    public func getVolume() async throws -> Int {
        let body = Data()
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.getVolume.rawValue,
            body: body
        )

        guard case .reply(.volume(let volume)) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }

        return volume
    }

    /// Set the volume level (0-100)
    public func setVolume(_ level: Int) async throws {
        let body = ProtocolEncoder.encodeSetVolume(level)
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.setVolume.rawValue,
            body: body
        )

        guard case .reply(.success) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }
    }

    public func enableEvent(_ eventType: EventType) async throws {
        print("[EVENT] Enabling event type: \(eventType) (fire-and-forget)")
        let body = ProtocolEncoder.encodeRegisterNotification(eventType)
        let data = ProtocolEncoder.encodeMessage(
            commandGroup: .basic,
            command: BasicCommand.registerNotification.rawValue,
            body: body
        )
        try await sendBytes(data)
        print("[EVENT] Sent enable event command for: \(eventType)")
    }
    
    public func sendTncDataFragment(_ fragment: TncDataFragment) async throws {
        let body = ProtocolEncoder.encodeTncDataFragment(fragment)
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.htSendData.rawValue,
            body: body
        )
        
        guard case .reply(.success) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }
    }
    
    public func getBeaconSettings() async throws -> BeaconSettings {
        var body = Data()
        body.append(2) // unknown field
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.readBSSSettings.rawValue,
            body: body
        )
        
        guard case .reply(.beaconSettings(let settings)) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }
        
        return settings
    }
    
    public func setBeaconSettings(_ settings: BeaconSettings) async throws {
        let body = ProtocolEncoder.encodeBeaconSettings(settings)
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.writeBSSSettings.rawValue,
            body: body
        )
        
        guard case .reply(.success) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }
    }

    public func getAPRSPath() async throws -> String {
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.getAPRSPath.rawValue,
            body: Data()
        )

        guard case .reply(.aprsPath(let path)) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }

        return path
    }

    public func setAPRSPath(_ path: String) async throws {
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.setAPRSPath.rawValue,
            body: ProtocolEncoder.encodeAPRSPath(path)
        )

        guard case .reply(.success) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }
    }
    
    // MARK: - Region API
    
    public func getRegionName(_ regionID: Int) async throws -> String {
        let body = ProtocolEncoder.encodeReadRegionName(regionID)
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.readRegionName.rawValue,
            body: body
        )
        
        guard case .reply(.regionName(let name)) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }
        
        return name
    }
    
    public func setRegionName(_ regionID: Int, name: String) async throws {
        let body = ProtocolEncoder.encodeWriteRegionName(regionID: regionID, name: name)
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.writeRegionName.rawValue,
            body: body
        )
        
        guard case .reply(.success) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }
    }

    public func setCurrentRegionName(_ name: String) async throws {
        let body = ProtocolEncoder.encodeWriteRegionNameNameOnly(name)
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.writeRegionName.rawValue,
            body: body
        )

        guard case .reply(.success) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }
    }
    
    // MARK: - PF API
    
    public func getPF() async throws -> PFConfig {
        let body = ProtocolEncoder.encodeGetPF()
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.getPF.rawValue,
            body: body
        )
        
        guard case .reply(.pf(let pfConfig)) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }
        
        return pfConfig
    }
    
    public func setPF(_ pfConfig: PFConfig) async throws {
        let body = ProtocolEncoder.encodeSetPF(pfConfig)
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.setPF.rawValue,
            body: body
        )
        
        guard case .reply(.success) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }
    }

    public func getPFActionsRaw() async throws -> Data {
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.getPFActions.rawValue,
            body: Data()
        )

        guard case .reply(.pfActions(let data)) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }

        return data
    }
    
    public func setRegion(_ regionID: Int) async throws {
        let body = ProtocolEncoder.encodeSetRegion(regionID)
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.setRegion.rawValue,
            body: body
        )
        
        
        guard case .reply(.success) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }
    }

    public func setRegionChannel(regionID: Int, channelID: Int) async throws {
        let body = ProtocolEncoder.encodeWriteRegionChannel(regionID: regionID, channelID: channelID)
        let reply = try await sendCommandAndWaitForReply(
            commandGroup: .basic,
            command: BasicCommand.writeRegionCh.rawValue,
            body: body
        )
        
        guard case .reply(.success) = reply else {
            if case .reply(.error(let status, let message)) = reply {
                throw ProtocolError.commandFailed(status, message)
            }
            throw ProtocolError.invalidReply
        }
    }
}

/// Protocol errors
public enum ProtocolError: LocalizedError {
    case notImplemented
    case decodeError(String)
    case invalidMessage
    case invalidReply
    case timeout
    case commandFailed(ReplyStatus, String)
    case invalidCommandGroup
    case invalidPowerStatusType
    
    public var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "Protocol decoder not fully implemented"
        case .decodeError(let message):
            return "Failed to decode message: \(message)"
        case .invalidMessage:
            return "Invalid message format"
        case .invalidReply:
            return "Invalid reply format"
        case .timeout:
            return "Command timed out"
        case .commandFailed(let status, let message):
            return "Command failed: \(status) - \(message)"
        case .invalidCommandGroup:
            return "Invalid command group"
        case .invalidPowerStatusType:
            return "Invalid power status type"
        }
    }
}
