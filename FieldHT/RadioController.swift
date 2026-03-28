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
        do {
            try await connection.connect()
            try await hydrate()
        } catch {
            // Ensure a failed connect attempt doesn't leave the transport half-open.
            await disconnect()
            throw error
        }
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
        
        // Load beacon settings with a 1-second timeout — don't block hydration.
        // Use a typed task so we await the result safely instead of mutating a shared local var.
        let beaconTask = Task<BeaconSettings, Error> {
            return try await connection.getBeaconSettings()
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        beaconTask.cancel()
        let beaconSettings = (try? await beaconTask.value) ?? BeaconSettings.empty()

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
    public func hydrateChannels(deviceInfo: DeviceInfo? = nil, status: Status? = nil, regionID: Int? = nil) async throws -> [String] {
        let activeDeviceInfo = deviceInfo ?? self.deviceInfo
        var activeStatus = status ?? self.status
        
        let currentRegion = regionID ?? activeStatus.currRegion
        activeStatus.currRegion = currentRegion
        var regionDict: [Int: Channel] = [:]
        
        // Load region memory slots
        let maxChannelsToLoad = min(30, activeDeviceInfo.channelCount)
        for i in 0..<maxChannelsToLoad {
            let channel = try await connection.getChannel(i)
            
            regionDict[channel.channelID] = channel
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

    private func pollStatusUntilRegionMatches(_ regionID: Int, timeoutNanoseconds: UInt64 = 2_000_000_000, pollEveryNanoseconds: UInt64 = 200_000_000) async -> Status? {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if let status = try? await connection.getStatus(), status.currRegion == regionID {
                return status
            }
            try? await Task.sleep(nanoseconds: pollEveryNanoseconds)
        }
        return try? await connection.getStatus()
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
        let regionDict = self.channels[currentRegion] ?? [:]
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

    /// Get beacon settings
    public func getBeaconSettings() async throws -> BeaconSettings {
        return try await connection.getBeaconSettings()
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

    // MARK: - Power & Scan Commands

    public func setHTOnOff(_ isOn: Bool) async throws {
        try await connection.setHTOnOff(isOn)
    }

    public func setRadioMode(_ mode: Int) async throws {
        try await connection.setRadioMode(mode)
    }

    public func toggleScan() async throws {
        // 12 is the PFEffectType for TOGGLE_CH_SCAN in DO_PROG_FUNC
        try await connection.executePFAction(12)
    }

    // MARK: - Satellite mode (reverse-engineered)

    public func setFreqModeParameters(
        rxMHz: Double,
        txMHz: Double,
        rxSubAudio: SubAudio? = nil,
        txSubAudio: SubAudio? = nil
    ) async throws {
        let rxHzX = UInt32(max(0, Int((rxMHz * 1_000_000.0).rounded())))
        let txHzX = UInt32(max(0, Int((txMHz * 1_000_000.0).rounded())))
        try await connection.setFreqModeParameters(
            rxFreqHzX: rxHzX,
            txFreqHzX: txHzX,
            rxSubAudio: rxSubAudio,
            txSubAudio: txSubAudio
        )
        // Observed in BLE logs: firmware expects a follow-up status read (cmd 36).
        try await connection.getFreqModeStatus()
    }

    public func setSatModeInfo(
        name: String,
        rangeKm: Double,
        dopplerShiftHz: Int,
        azimuthDeg: Double,
        elevationDeg: Double,
        altitudeKm: Double
    ) async throws {
        try await connection.setSatModeInfo(
            name: name,
            rangeKm: rangeKm,
            dopplerShiftHz: dopplerShiftHz,
            azimuthDeg: azimuthDeg,
            elevationDeg: elevationDeg,
            altitudeKm: altitudeKm
        )
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

        #if DEBUG
        let regionCount = currentState.deviceInfo.regionCount
        let priorRegion = currentState.status.currRegion
        var beforeNames: [String] = []
        if regionCount > 0 {
            do {
                beforeNames = []
                for i in 0..<regionCount {
                    beforeNames.append(try await connection.getRegionName(i))
                }
                print("[REGION-RENAME] Before: \(beforeNames.enumerated().map { "\($0.offset):\($0.element)" }.joined(separator: ", "))")
            } catch {
                print("[REGION-RENAME] Warning: failed to read names before rename: \(error)")
                beforeNames = []
            }
        }
        #endif

        // Try name-only write FIRST (safer - only affects the name, no region config side effects)
        // Then fall back to "write with region ID" if needed
        do {
            try await connection.setCurrentRegionName(name)
        } catch {
            #if DEBUG
            print("[REGION-RENAME] Name-only write failed (\(error)); trying write with region ID")
            // Fallback: write with region ID included
            do {
                try await connection.setRegionName(regionID, name: name)
            } catch {
                #if DEBUG
                print("[REGION-RENAME] Region+name write also failed (\(error)); trying switch+name-only path")
                // Last resort: switch to target region, write name-only, restore
                do {
                    if priorRegion != regionID {
                        try await connection.setRegion(regionID)
                        try await Task.sleep(nanoseconds: 250_000_000)
                    }
                    try await connection.setCurrentRegionName(name)
                    if priorRegion != regionID {
                        try await connection.setRegion(priorRegion)
                        try await Task.sleep(nanoseconds: 250_000_000)
                    }
                } catch {
                    print("[REGION-RENAME] All paths failed (\(error))")
                    throw error
                }
                #else
                throw error
                #endif
            }
            #else
            throw error
            #endif
        }

        #if DEBUG
        if regionCount > 0 {
            do {
                var afterNames: [String] = []
                for i in 0..<regionCount {
                    afterNames.append(try await connection.getRegionName(i))
                }

                if !beforeNames.isEmpty, beforeNames.count == afterNames.count {
                    let changed = zip(beforeNames, afterNames)
                        .enumerated()
                        .compactMap { idx, pair in pair.0 == pair.1 ? nil : idx }
                    print("[REGION-RENAME] Changed indices: \(changed)")
                }
                print("[REGION-RENAME] After: \(afterNames.enumerated().map { "\($0.offset):\($0.element)" }.joined(separator: ", "))")

                currentState.regionNames = afterNames
            } catch {
                print("[REGION-RENAME] Warning: failed to read names after rename: \(error)")
                var newRegions = currentState.regionNames
                if regionID < newRegions.count {
                    newRegions[regionID] = name
                }
                currentState.regionNames = newRegions
            }
        }
        #else
        // Update local state
        var newRegions = currentState.regionNames
        if regionID < newRegions.count {
            newRegions[regionID] = name
        }
        currentState.regionNames = newRegions
        #endif

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

        // Give the radio a moment to apply the change, then confirm via status poll.
        try? await Task.sleep(nanoseconds: 200_000_000)
        let updatedStatus = await pollStatusUntilRegionMatches(regionID)

        // Hydrate channels explicitly for the target region, independent of any delayed status event.
        _ = try await hydrateChannels(deviceInfo: currentState.deviceInfo, status: updatedStatus, regionID: regionID)
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
    
    /// Get PF configuration
    public func getPF() async throws -> PFConfig {
        return try await connection.getPF()
    }
    
    /// Set PF configuration
    public func setPF(_ config: PFConfig) async throws {
        try await connection.setPF(config)
    }

    // MARK: - Beacon Settings

    // MARK: - Volume Control

    /// Get the current volume level (0-100)
    public func volume() async throws -> Int {
        return try await connection.getVolume()
    }

    /// Set the volume level (0-100)
    public func setVolume(_ level: Int) async throws {
        try await connection.setVolume(level)
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
