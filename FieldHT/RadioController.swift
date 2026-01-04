import Foundation
import Combine

/// High-level interface for controlling Benshi radios
public class RadioController: ObservableObject {
    private let connection: CommandConnection
    
    @Published public private(set) var state: RadioState?
    private var channels: [Int: [Int: Channel]] = [:] // regionID -> channelID -> Channel
    
    private init(connection: CommandConnection) {
        self.connection = connection
    }
    
    /// Create a new BLE radio controller
    public static func newBLE(deviceUUID: UUID, radioManager: RadioManager) -> RadioController {
        let connection = CommandConnection.newBLE(deviceUUID: deviceUUID, radioManager: radioManager)
        return RadioController(connection: connection)
    }
    
    /// Check if connected
    public var isConnected: Bool {
        return connection.isConnected && state != nil
    }
    
    /// Device info
    public var deviceInfo: DeviceInfo {
        return state?.deviceInfo ?? DeviceInfo.empty()
    }
    
    /// Channels for current region
    public var channelsForCurrentRegion: [Channel] {
        guard let state = state else { return [] }
        let regionDict = channels[state.status.currRegion] ?? [:]
        return regionDict.values.sorted { $0.channelID < $1.channelID }
    }
    
    /// Get channels for a specific region
    public func channels(forRegion regionID: Int) -> [Channel] {
        let regionDict = channels[regionID] ?? [:]
        return regionDict.values.sorted { $0.channelID < $1.channelID }
    }
    
    /// Region Names
    public var regionNames: [String] {
        return state?.regionNames ?? []
    }
    
    /// Settings
    public var settings: Settings {
        return state?.settings ?? Settings.empty()
    }
    
    /// Status
    public var status: Status {
        return state?.status ?? Status.empty()
    }
    
    /// Beacon settings
    public var beaconSettings: BeaconSettings {
        return state?.beaconSettings ?? BeaconSettings.empty()
    }
    
    /// Connect to the radio
    public func connect() async throws {
        try await connection.connect()
        try await hydrate()
    }
    
    /// Disconnect from the radio
    public func disconnect() async {
        await connection.disconnect()
        await MainActor.run {
            state = nil
        }
        channels.removeAll()
    }
    
    /// Hydrate state from radio
    public func hydrate() async throws {
        let deviceInfo = try await connection.getDeviceInfo()
        let settings = try await connection.getSettings()
        let status = try await connection.getStatus()
        
        let regionNames = try await hydrateChannels(deviceInfo: deviceInfo, status: status)
        
        let beaconSettings = try await connection.getBeaconSettings()

        // Register event handler if not already done
        _ = connection.addEventHandler { [weak self] event in
            self?.handleEvent(event)
        }
        
        // Enable status changed event
        try await connection.enableEvent(.htStatusChanged)
        
        // Initialize state
        let newState = RadioState(
            deviceInfo: deviceInfo,
            beaconSettings: beaconSettings,
            status: status,
            settings: settings,
            regionNames: regionNames
        )
        await MainActor.run {
            self.state = newState
        }
    }
    
    /// Lightweight hydration for just channels and region names
    @discardableResult
    public func hydrateChannels(deviceInfo: DeviceInfo? = nil, status: Status? = nil) async throws -> [String] {
        let activeDeviceInfo = deviceInfo ?? self.deviceInfo
        let activeStatus = status ?? self.status
        
        let currentRegion = activeStatus.currRegion
        var regionDict: [Int: Channel] = [:]
        
        // Load region memory slots
        var validChannelCount = 0
        let maxChannelsToLoad = min(30, activeDeviceInfo.channelCount)
        
        for i in 0..<activeDeviceInfo.channelCount {
            let channel = try await connection.getChannel(i)
            
            regionDict[channel.channelID] = channel
            
            if channel.rxFreq > 0 {
                validChannelCount += 1
            }
            
            
        }
        
        // Explicitly load VFO channels (ids 252, 251)
        for vfoID in [252, 251] {
            do {
                let channel = try await connection.getChannel(vfoID)
                regionDict[channel.channelID] = channel
            } catch {
                print("Could not load VFO channel \(vfoID): \(error)")
            }
        }
        
        // Store the completed channel dictionary for this region
        channels[currentRegion] = regionDict
        
        // Load regions names
        var regionNames: [String] = []
        if activeDeviceInfo.regionCount > 0 {
            for i in 0..<activeDeviceInfo.regionCount {
                do {
                    let name = try await connection.getRegionName(i)
                    regionNames.append(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Group \(i + 1)" : name)
                } catch {
                    regionNames.append("Group \(i + 1)")
                }
            }
        }
        
        // Update state if it exists
        if var currentState = state {
            currentState.regionNames = regionNames
            currentState.status = activeStatus
            await MainActor.run {
                self.state = currentState
            }
        }
        
        return regionNames
    }
    
    /// Handle incoming events
    private func handleEvent(_ event: EventMessage) {
        guard var currentState = state else { return }
        
        Task { @MainActor in
            switch event {
            case .statusChanged(let status):
                currentState.status = status
                self.state = currentState
            case .channelChanged(let channel):
                // Update channel in the appropriate region
                let currentRegion = currentState.status.currRegion
                var regionDict = self.channels[currentRegion] ?? [:]
                regionDict[channel.channelID] = channel
                self.channels[currentRegion] = regionDict
                
                // We might need to trigger an update if the current channel changed
                // but since channels are separate from state struct (except for convenience),
                // we might want to consider putting channels IN state.
                // For now, simple state update to trigger UI:
                self.objectWillChange.send()
                
            case .settingsChanged(let settings):
                currentState.settings = settings
                self.state = currentState
            default:
                break
            }
        }
    }
    
    /// Set channel directly
    public func setChannel(_ channel: Channel) async throws {
        guard let currentState = state else {
            throw RadioError.stateNotInitialized
        }
        
        try await connection.setChannel(channel)
        
        let currentRegion = currentState.status.currRegion
        var regionDict = self.channels[currentRegion] ?? [:]
        regionDict[channel.channelID] = channel
        self.channels[currentRegion] = regionDict
        
        await MainActor.run {
            self.objectWillChange.send()
        }
    }
    
    /// Update specific fields of a channel
    public func setChannel(_ channelID: Int, name: String? = nil, txFreq: Double? = nil, rxFreq: Double? = nil) async throws {
        guard let currentState = state else {
            throw RadioError.stateNotInitialized
        }
        
        let currentRegion = currentState.status.currRegion
        var regionDict = self.channels[currentRegion] ?? [:]
        var channel: Channel
        if let existing = regionDict[channelID] {
            channel = existing
        } else if channelID >= 250 {
            channel = Channel.empty(channelID: channelID)
        } else {
            throw RadioError.invalidChannelID
        }
        
        // Update channel properties if provided
        if let name = name {
            channel.name = name
        }
        if let txFreq = txFreq {
            channel.txFreq = txFreq
        }
        if let rxFreq = rxFreq {
            channel.rxFreq = rxFreq
        }
        
        // Use the direct method
        try await setChannel(channel)
    }
    
    /// Get battery voltage
    public func batteryVoltage() async throws -> Double {
        return try await connection.getBatteryVoltage()
    }
    
    /// Get battery level
    public func batteryLevel() async throws -> Int {
        return try await connection.getBatteryLevel()
    }
    
    /// Get battery level as percentage (0-100)
    public func batteryLevelAsPercentage() async throws -> Int {
        return try await connection.getBatteryLevelAsPercentage()
    }
    
    /// Get position
    public func position() async throws -> Position {
        return try await connection.getPosition()
    }
    
    /// Set beacon settings
    public func setBeaconSettings(_ settings: BeaconSettings) async throws {
        guard var currentState = state else {
            throw RadioError.stateNotInitialized
        }
        
        try await connection.setBeaconSettings(settings)
        
        currentState.beaconSettings = settings
        await MainActor.run {
            self.state = currentState
        }
    }
    
    /// Set settings
    public func setSettings(_ newSettings: Settings) async throws {
        guard var currentState = state else {
            throw RadioError.stateNotInitialized
        }
        
        try await connection.setSettings(newSettings)
        
        currentState.settings = newSettings
        await MainActor.run {
            self.state = currentState
        }
    }
    
    /// Send TNC data
    public func sendTncData(_ data: Data) async throws {
        if data.count > 50 {
            throw RadioError.dataTooLong
        }
        
        let fragment = TncDataFragment(
            isFinalFragment: true,
            fragmentID: 0,
            data: data
        )
        
        try await connection.sendTncDataFragment(fragment)
    }
    
    /// Set region name
    public func setRegionName(_ regionID: Int, name: String) async throws {
        guard var currentState = state else {
            throw RadioError.stateNotInitialized
        }
        
        guard regionID < currentState.deviceInfo.regionCount else {
            throw RadioError.invalidChannelID // reusing error or make new one
        }
        
        try await connection.setRegionName(regionID, name: name)
        
        // Update local state
        var newRegions = currentState.regionNames
        if regionID < newRegions.count {
            newRegions[regionID] = name
        }
        
        currentState.regionNames = newRegions
        await MainActor.run {
            self.state = currentState
        }
    }
    
    /// Set current region
    public func setRegion(_ regionID: Int) async throws {
        guard let currentState = state else {
            throw RadioError.stateNotInitialized
        }
        
        guard regionID < currentState.deviceInfo.regionCount else {
            throw RadioError.invalidChannelID
        }
        
        try await connection.setRegion(regionID)
        // Note: setting region might change status, but we wait for event or next poll
    }
    
    /// Assign channel to region
    public func assignChannelToRegion(regionID: Int, channelID: Int) async throws {
        guard let currentState = state else {
            throw RadioError.stateNotInitialized
        }
        
        guard regionID < currentState.deviceInfo.regionCount else {
            throw RadioError.invalidChannelID
        }
        
        try await connection.setRegionChannel(regionID: regionID, channelID: channelID)
    }

    /// Add event handler
    @discardableResult
    public func addEventHandler(_ handler: @escaping EventHandler) -> () -> Void {
        return connection.addEventHandler(handler)
    }
}

// Extension for empty channel placeholder
extension Channel {
    static func empty(channelID: Int = 0) -> Channel {
        return Channel(
                 channelID: channelID,
                 txMod: ModulationType.fm,
                 txFreq: 0.0,
                 rxMod: ModulationType.fm,
                 rxFreq: 0.0,
                 txSubAudio: nil,
                 rxSubAudio: nil,
                 scan: false,
                 txAtMaxPower: false,
                 talkAround: false,
                 bandwidth: BandwidthType.narrow,
                 preDeEmphBypass: false,
                 sign: false,
                 txAtMedPower: false,
                 txDisable: false,
                 fixedFreq: false,
                 fixedBandwidth: false,
                 fixedTxPower: false,
                 mute: false,
                 name: ""
             )
    }
}

/// Radio errors
public enum RadioError: LocalizedError {
    case stateNotInitialized
    case invalidChannelID
    case connectionFailed
    case dataTooLong
    
    public var errorDescription: String? {
        switch self {
        case .stateNotInitialized:
            return "Radio state not initialized. Call connect() first."
        case .invalidChannelID:
            return "Invalid channel ID"
        case .connectionFailed:
            return "Connection failed"
        case .dataTooLong:
            return "Data too long (max 50 bytes). Fragmentation not yet implemented."
        }
    }
}


