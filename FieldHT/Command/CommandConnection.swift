import Foundation

/// Event handler type
public typealias EventHandler = (EventMessage) -> Void

/// Command connection - low-level interface for communicating with the radio
public class CommandConnection: BLEConnectionDelegate {
    private let bleConnection: BLEConnection
    private var eventHandlers: [UUID: EventHandler] = [:]
    private var pendingReplies: [UInt16: (CheckedContinuation<RadioMessage, Error>)] = [:]
    private let queue = DispatchQueue(label: "com.benlink.command")
    
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
    public static func newBLE(deviceUUID: UUID,radioManager:RadioManager) -> CommandConnection {
        let ble = BLEConnection(deviceUUID: deviceUUID,radioManager: radioManager)
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
            for (_, continuation) in self.pendingReplies {
                continuation.resume(throwing: BLEError.notConnected)
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
            for (_, continuation) in self.pendingReplies {
                continuation.resume(throwing: BLEError.notConnected)
            }
            self.pendingReplies.removeAll()
        }
    }
    
    public func connection(_ connection: BLEConnection, didReceiveData data: Data) {
        let hex = data.map { String(format: "%02hhx", $0) }.joined()
        print("[BLE-RX] Raw (\(data.count) bytes): \(hex)")
        
        queue.async {
            do {
                let message = try ProtocolDecoder.decodeMessage(data)
                print("[BLE-RX] Decoded -> Reply: \(message.isReply), Grp: \(message.commandGroup), Cmd: \(message.command), Body: \(message.body.map { String(format: "%02hhx", $0) }.joined())")
                
                // Handle replies
                if message.isReply {
                    if let continuation = self.pendingReplies[message.command] {
                        self.pendingReplies.removeValue(forKey: message.command)
                        
                        let reply = try self.decodeReply(message: message)
                        continuation.resume(returning: .reply(reply))
                    }
                } else {
                    // Handle events
                    if message.commandGroup == .basic && message.command == BasicCommand.eventNotification.rawValue {
                        print("[EVENT] Received event notification, body: \(message.body.map { String(format: "%02hhx", $0) }.joined())")
                        let event = try self.decodeEvent(message: message)
                        print("[EVENT] Decoded event: \(event)")
                        for handler in self.eventHandlers.values {
                            handler(event)
                        }
                    } else {
                        print("[BLE-RX] Unhandled non-reply message: Grp=\(message.commandGroup) Cmd=\(message.command)")
                    }
                }
            } catch {
                print("Error decoding message: \(error)")
            }
        }
    }
    
    // MARK: - Reply Decoding
    
    private func decodeReply(message: ProtocolMessage) throws -> ReplyMessage {
        switch (message.commandGroup, message.command) {
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
                return .batteryVoltage(value as! Double)
            case .batteryLevel:
                return .batteryLevel(value as! Int)
            case .batteryLevelAsPercentage:
                return .batteryLevelAsPercentage(value as! Int)
            case .rcBatteryLevel:
                return .error(.success, "RC battery level not implemented in reply")
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
            
        case (.basic, BasicCommand.htSendData.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to send TNC data")
            }
            return .success
            
            return .success
            
        case (.basic, BasicCommand.readRegionName.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to get region name")
            }
            let bodyData = message.body.dropFirst(1)
            let name = try ProtocolDecoder.decodeRegionName(bodyData)
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

            return .success
            
        case (.basic, BasicCommand.writeRegionCh.rawValue):
            let replyStatus = try decodeReplyStatus(message.body)
            guard replyStatus == .success else {
                return .error(replyStatus, "Failed to set region channel")
            }
            return .success

        default:
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
            return .unknown(message.body)
        }
        
        let eventData = try stream.readBytes(stream.remaining / 8)
        
        switch eventType {
        case .htStatusChanged:
            let status = try ProtocolDecoder.decodeStatus(eventData)
            return .statusChanged(status)
            
        case .htChChanged:
            let channel = try ProtocolDecoder.decodeChannel(eventData)
            return .channelChanged(channel)
            
        case .htSettingsChanged:
            let settings = try ProtocolDecoder.decodeSettings(eventData)
            return .settingsChanged(settings)
            
        case .dataRxd:
            let fragment = try ProtocolDecoder.decodeTncDataFragment(eventData)
            return .tncDataFragmentReceived(fragment)
            
        default:
            return .unknown(eventData)
        }
    }
    
    // MARK: - Command API
    
    private func sendCommandAndWaitForReply(
        commandGroup: CommandGroup,
        command: UInt16,
        body: Data,
        timeout: TimeInterval = 5.0
    ) async throws -> RadioMessage {
        let hexBody = body.map { String(format: "%02hhx", $0) }.joined()
        print("[BLE-TX] Sending -> Grp: \(commandGroup), Cmd: \(command), Body: \(hexBody)")
        
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                // If there's already a pending reply for this command, fail it to prevent leaking
                if let existing = self.pendingReplies[command] {
                    existing.resume(throwing: CancellationError())
                }
                
                self.pendingReplies[command] = continuation
                
                let messageData = ProtocolEncoder.encodeMessage(
                    commandGroup: commandGroup,
                    command: command,
                    isReply: false,
                    body: body
                )
                
                Task {
                    do {
                        try await self.bleConnection.send(messageData)
                        
                        // Set timeout
                        // We use a separate task for waiting, but must dispatch back to queue to access state
                        Task {
                            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                            self.queue.async {
                                if let continuation = self.pendingReplies[command] {
                                    print("[BLE-CMD-ERR] Command \(command) timed out waiting for reply")
                                    self.pendingReplies.removeValue(forKey: command)
                                    continuation.resume(throwing: ProtocolError.timeout)
                                }
                            }
                        }
                    } catch {
                        print("[BLE-CMD-ERR] Command \(command) failed to send: \(error)")
                        self.queue.async {
                            // Only resume if still pending (not timed out or replied)
                            if let continuation = self.pendingReplies[command] {
                                self.pendingReplies.removeValue(forKey: command)
                                continuation.resume(throwing: error)
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
        
        // RC battery level handling would go here
        throw ProtocolError.notImplemented
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
