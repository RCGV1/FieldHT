import Foundation
import Combine

/// High-level interface for controlling Benshi radios
public class RadioController: ObservableObject {
    private let connection: CommandConnection
    
    @Published public private(set) var state: RadioState?
    @Published public private(set) var frequencyScanStatus: FrequencyModeStatus?
    @Published public private(set) var frequencyScanStatusUpdatedAt: Date?
    @Published public private(set) var frequencyRanges: DeviceFrequencyRanges?
    private var channels: [Int: [Int: Channel]] = [:] // regionID -> channelID -> Channel
    private var backgroundHydrationTask: Task<Void, Never>?
    private var removeConnectionEventHandler: (() -> Void)?
    
    private init(connection: CommandConnection) {
        self.connection = connection
    }
    
    /// Create a new BLE radio controller
    public static func newBLE(deviceUUID: UUID, radioManager: RadioManager) -> RadioController {
        let connection = CommandConnection.newBLE(
            deviceUUID: deviceUUID,
            radioManager: radioManager,
            enableStateRestoration: true
        )
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

    public var supportsFrequencyScanStatusNotifications: Bool {
        deviceInfo.firmwareVersion >= 143
    }

    private func isValidChannelID(_ channelID: Int, deviceInfo: DeviceInfo) -> Bool {
        (0..<deviceInfo.channelCount).contains(channelID) || [251, 252, 253].contains(channelID)
    }

    private func clampedRegionID(_ regionID: Int, regionCount: Int? = nil) -> Int {
        let availableRegionCount = regionCount ?? state?.regionNames.count ?? state?.deviceInfo.regionCount ?? 0
        guard availableRegionCount > 0 else { return 0 }
        guard (0..<availableRegionCount).contains(regionID) else { return 0 }
        return regionID
    }

    private func sanitizedStatus(_ status: Status, fallback: Status) -> Status {
        var sanitized = status
        sanitized.currRegion = clampedRegionID(status.currRegion)
        return sanitized
    }

    private func shouldAcceptRadioStatusEvent(_ status: Status, currentState: RadioState) -> Bool {
        if !status.isPowerOn && currentState.status.isPowerOn {
            return false
        }

        let regionCount = max(currentState.regionNames.count, currentState.deviceInfo.regionCount)
        if regionCount > 0 && !(0..<regionCount).contains(status.currRegion) {
            return false
        }

        if !isValidChannelID(status.currChID, deviceInfo: currentState.deviceInfo) {
            return false
        }

        return true
    }
    
    /// Channels for current region
    public var channelsForCurrentRegion: [Channel] {
        guard let state = state else { return [] }
        let regionDict = channels[clampedRegionID(state.status.currRegion)] ?? [:]
        return regionDict.values.sorted { $0.channelID < $1.channelID }
    }

    /// Get one channel by its radio slot ID from the current region.
    public func channel(channelID: Int) -> Channel? {
        guard let state = state else { return nil }
        return channels[clampedRegionID(state.status.currRegion)]?[channelID]
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

    /// Refresh settings from the radio and update local state.
    @discardableResult
    public func refreshSettings() async throws -> Settings {
        let refreshedSettings = try await connection.getSettings()

        if var currentState = state {
            currentState.settings = refreshedSettings
            await MainActor.run {
                self.state = currentState
            }
        }

        return refreshedSettings
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
        backgroundHydrationTask?.cancel()
        backgroundHydrationTask = nil
        removeConnectionEventHandler?()
        removeConnectionEventHandler = nil
        await connection.disconnect()
        await MainActor.run {
            state = nil
        }
        channels.removeAll()
    }

    public func handleTransportDidDisconnect() {
        backgroundHydrationTask?.cancel()
        backgroundHydrationTask = nil
        removeConnectionEventHandler?()
        removeConnectionEventHandler = nil

        Task { @MainActor in
            self.state = nil
        }
        channels.removeAll()
    }
    
    /// Hydrate state from radio
    public func hydrate() async throws {
        let deviceInfo = try await connection.getDeviceInfo()
        let settings = try await connection.getSettings()
        let status = try await connection.getStatus()

        removeConnectionEventHandler?()
        removeConnectionEventHandler = connection.addEventHandler { [weak self] event in
            self?.handleEvent(event)
        }

        var eventTypes: [EventType] = [
            EventType.htStatusChanged,
            .htChChanged,
            .htSettingsChanged,
            .radioStatusChanged,
            .bssSettingsChanged
        ]
        if deviceInfo.firmwareVersion >= 143 {
            eventTypes.append(.frequencyScanStatusChanged)
        }
        for eventType in eventTypes {
            try? await connection.enableEvent(eventType)
        }

        let regionNames = Self.placeholderRegionNames(regionCount: deviceInfo.regionCount)
        await hydrateSelectedChannels(deviceInfo: deviceInfo, settings: settings, status: status)

        let newState = RadioState(
            deviceInfo: deviceInfo,
            beaconSettings: BeaconSettings.empty(),
            status: status,
            settings: settings,
            regionNames: regionNames
        )
        await MainActor.run {
            self.state = newState
        }

        startBackgroundHydration(deviceInfo: deviceInfo, status: status)
    }

    private func hydrateSelectedChannels(deviceInfo: DeviceInfo, settings: Settings, status: Status) async {
        let startedAt = Date()
        let currentRegion = clampedRegionID(status.currRegion, regionCount: deviceInfo.regionCount)
        var regionDict = channels[currentRegion] ?? [:]
        let channelIDs = Set([settings.channelA, settings.channelB, status.currChID])
            .filter { isValidChannelID($0, deviceInfo: deviceInfo) }

        for channelID in channelIDs.sorted() {
            do {
                let channel = try await connection.getChannel(channelID)
                regionDict[channel.channelID] = channel
            } catch {
                print("RadioController: failed to hydrate selected channel \(channelID): \(error)")
            }
        }

        channels[currentRegion] = regionDict

        if BLECaptureStore.isEnabled {
            await BLECaptureStore.shared.recordNote(
                category: "selected_channels_hydrated",
                message: "Hydrated selected channels before first connected UI render",
                fields: [
                    "channel_ids": channelIDs.sorted().map(String.init).joined(separator: ","),
                    "elapsed_ms": String(Int(Date().timeIntervalSince(startedAt) * 1000.0)),
                    "region_id": String(currentRegion)
                ]
            )
        }
    }
    
    /// Lightweight hydration for just channels and region names
    @discardableResult
    public func hydrateChannels(deviceInfo: DeviceInfo? = nil, status: Status? = nil, regionID: Int? = nil) async throws -> [String] {
        let activeDeviceInfo = deviceInfo ?? self.deviceInfo
        var activeStatus = status ?? self.status
        
        let currentRegion = clampedRegionID(regionID ?? activeStatus.currRegion, regionCount: activeDeviceInfo.regionCount)
        activeStatus.currRegion = currentRegion
        var regionDict = channels[currentRegion] ?? [:]
        
        // Load region memory slots
        let maxChannelsToLoad = min(30, activeDeviceInfo.channelCount)
        for i in 0..<maxChannelsToLoad {
            if Task.isCancelled {
                throw CancellationError()
            }

            do {
                let channel = try await connection.getChannel(i)
                regionDict[channel.channelID] = channel
            } catch {
                print("Could not load channel \(i): \(error)")
            }

            // The radio is sensitive to bursts of read commands immediately
            // after connecting. Keep hydration cooperative with live controls.
            try await Task.sleep(nanoseconds: 80_000_000)
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
                if Task.isCancelled {
                    throw CancellationError()
                }

                do {
                    let name = try await connection.getRegionName(i)
                    regionNames.append(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Group \(i + 1)" : name)
                } catch {
                    regionNames.append("Group \(i + 1)")
                }

                try await Task.sleep(nanoseconds: 80_000_000)
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

    private func startBackgroundHydration(deviceInfo: DeviceInfo, status: Status) {
        backgroundHydrationTask?.cancel()
        backgroundHydrationTask = Task { [weak self] in
            guard let self else { return }

            let startedAt = Date()

            do {
                let beaconSettings = try await self.loadBeaconSettingsWithTimeout()
                if Task.isCancelled { return }

                if var currentState = self.state {
                    currentState.beaconSettings = beaconSettings
                    await MainActor.run {
                        self.state = currentState
                    }
                }

                for eventType in [
                    EventType.userAction,
                    .systemEvent,
                    .positionChanged,
                    .dataRxd,
                    .dataTxd,
                    .newInquiryData,
                    .restoreFactorySettings,
                    .ringingStopped
                ] {
                    if Task.isCancelled { return }
                    try? await self.connection.enableEvent(eventType)
                }

                do {
                    try await self.connection.syncTime()
                    print("RadioController: synced radio time")
                } catch {
                    print("RadioController: failed to sync radio time: \(error)")
                }

                _ = try await self.hydrateChannels(deviceInfo: deviceInfo, status: status)
                let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000.0)
                print("RadioController: background hydration finished in \(elapsedMs)ms")
                if BLECaptureStore.isEnabled {
                    await BLECaptureStore.shared.recordNote(
                        category: "background_hydration_complete",
                        message: "Finished radio background hydration",
                        fields: ["elapsed_ms": String(elapsedMs)]
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                print("RadioController: background hydration failed: \(error)")
                if BLECaptureStore.isEnabled {
                    await BLECaptureStore.shared.recordNote(
                        category: "background_hydration_failed",
                        message: "Radio background hydration failed",
                        fields: ["error": error.localizedDescription]
                    )
                }
            }
        }
    }

    private func loadBeaconSettingsWithTimeout(timeoutNanoseconds: UInt64 = 1_000_000_000) async throws -> BeaconSettings {
        let beaconTask = Task<BeaconSettings, Error> {
            try await connection.getBeaconSettings()
        }

        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            beaconTask.cancel()
        }
        defer { timeoutTask.cancel() }

        return (try? await beaconTask.value) ?? BeaconSettings.empty()
    }

    private static func placeholderRegionNames(regionCount: Int) -> [String] {
        guard regionCount > 0 else { return [] }
        return (0..<regionCount).map { "Group \($0 + 1)" }
    }

    public func syncTime(_ date: Date = Date()) async throws {
        try await connection.syncTime(date)
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
                currentState.status = sanitizedStatus(status, fallback: currentState.status)
                self.state = currentState
            case .radioStatusChanged(let status):
                guard shouldAcceptRadioStatusEvent(status, currentState: currentState) else {
                    print("RadioController: ignoring implausible radioStatusChanged event \(status)")
                    return
                }
                currentState.status = sanitizedStatus(status, fallback: currentState.status)
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
            case .beaconSettingsChanged(let settings):
                currentState.beaconSettings = settings
                self.state = currentState
            case .positionChanged(let position):
                print("RadioController: positionChanged \(position)")
            case .tncDataFragmentReceived(let fragment):
                print("RadioController: dataRxd fragment=\(fragment.fragmentID) final=\(fragment.isFinalFragment) bytes=\(fragment.data.count)")
            case .tncDataFragmentTransmitted(let fragment):
                print("RadioController: dataTxd fragment=\(fragment.fragmentID) final=\(fragment.isFinalFragment) bytes=\(fragment.data.count)")
            case .frequencyModeStatus(let status):
                self.frequencyScanStatus = status
                self.frequencyScanStatusUpdatedAt = .now
            case .raw(let eventType, let data):
                let hex = data.map { String(format: "%02hhx", $0) }.joined()
                print("RadioController: raw event \(eventType) body=\(hex)")
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

    /// Get RC (hand microphone / speaker-mic) battery level
    public func rcBatteryLevel() async throws -> Int {
        return try await connection.getRCBatteryLevel()
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

    public func getAPRSPath() async throws -> String {
        try await connection.getAPRSPath()
    }

    public func setAPRSPath(_ path: String) async throws {
        try await connection.setAPRSPath(path)
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

    public func setDigitalSignalEnabled(_ isEnabled: Bool) async throws {
        try await connection.setDigitalSignalEnabled(isEnabled)
    }

    public func toggleScan() async throws {
        // 12 is the PFEffectType for TOGGLE_CH_SCAN in DO_PROG_FUNC
        try await connection.executePFAction(12)
    }

    // MARK: - Frequency mode

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
            txSubAudio: txSubAudio,
            mode: .satellite,
            extendedParameter: 0x61A8
        )
        _ = try await connection.getFreqModeStatus()
    }

    public func setFrequencyScan(
        frequencyMHz: Double,
        mode: FrequencyMode,
        step: FrequencyScanStep,
        rxSubAudio: SubAudio?,
        txSubAudio: SubAudio?
    ) async throws {
        let frequencyHz = UInt32(max(0, Int((frequencyMHz * 1_000_000.0).rounded())))
        try await connection.setFreqModeParameters(
            rxFreqHzX: frequencyHz,
            txFreqHzX: frequencyHz,
            rxSubAudio: rxSubAudio,
            txSubAudio: txSubAudio,
            mode: mode,
            step: step
        )
    }

    public func getFrequencyScanStatus() async throws -> FrequencyModeStatus {
        try await connection.getFreqModeStatus()
    }

    public func getFrequencyRanges() async throws -> DeviceFrequencyRanges {
        let ranges = try await connection.getFrequencyRanges()
        await MainActor.run {
            self.frequencyRanges = ranges
        }
        return ranges
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
        if data.count > 330 {
            throw RadioError.dataTooLong
        }

        for fragment in TncDataFragment.fragments(for: data) {
            try await connection.sendTncDataFragment(fragment)
        }
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

    /// Read a single memory slot without leaving the radio in another group.
    public func memoryChannel(inRegion regionID: Int, slot: Int) async throws -> Channel {
        guard let currentState = state,
              (0..<currentState.deviceInfo.regionCount).contains(regionID),
              (0..<currentState.deviceInfo.channelCount).contains(slot) else {
            throw RadioError.invalidChannelID
        }

        let previousRegion = currentState.status.currRegion
        let needsRestore = previousRegion != regionID

        do {
            if needsRestore {
                try await connection.setRegion(regionID)
                guard await pollStatusUntilRegionMatches(regionID)?.currRegion == regionID else {
                    throw RadioError.connectionFailed
                }
            }

            let channel = try await connection.getChannel(slot)

            if needsRestore {
                try await connection.setRegion(previousRegion)
                _ = await pollStatusUntilRegionMatches(previousRegion)
            }

            return channel
        } catch {
            if needsRestore {
                try? await connection.setRegion(previousRegion)
            }
            throw error
        }
    }

    /// Save a detected receive frequency as a receive-only memory channel.
    public func saveScanHit(
        frequencyMHz: Double,
        rxSubAudio: SubAudio?,
        inRegion regionID: Int,
        slot: Int
    ) async throws {
        guard let currentState = state,
              (0..<currentState.deviceInfo.regionCount).contains(regionID),
              (0..<currentState.deviceInfo.channelCount).contains(slot) else {
            throw RadioError.invalidChannelID
        }

        var channel = Channel.empty(channelID: slot)
        channel.rxFreq = frequencyMHz
        channel.txFreq = frequencyMHz
        channel.rxSubAudio = rxSubAudio
        channel.txDisable = true
        channel.scan = true
        channel.name = String(format: "SCAN %.1f", frequencyMHz)

        try await connection.setRegionChannel(regionID: regionID, slot: slot, channel: channel)

        var regionChannels = channels[regionID] ?? [:]
        regionChannels[slot] = channel
        channels[regionID] = regionChannels
        objectWillChange.send()
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

    public func getPFActionsRaw() async throws -> Data {
        try await connection.getPFActionsRaw()
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
            return "Data too long (max 330 bytes)."
        }
    }
}
