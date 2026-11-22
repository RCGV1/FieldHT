import Foundation
import Combine

/// High-level interface for controlling Benshi radios
public class RadioController: ObservableObject {
    private enum ChannelHydrationDecision {
        case suspended
        case waitForRegionSwitch
        case waitForExisting(Task<[String], Error>, canJoin: Bool)
        case started(UUID, Task<[String], Error>)
    }

    private let connection: CommandConnection
    
    @Published public private(set) var state: RadioState?
    @Published public private(set) var frequencyScanStatus: FrequencyModeStatus?
    @Published public private(set) var frequencyScanStatusUpdatedAt: Date?
    @Published public private(set) var frequencyRanges: DeviceFrequencyRanges?
    @Published public private(set) var fmRadioStatus: FMRadioStatus?
    @Published public private(set) var isPerformingMaintenance = false
    private var channels: [Int: [Int: Channel]] = [:] // regionID -> channelID -> Channel
    private var backgroundHydrationTask: Task<Void, Never>?
    private var channelHydrationTask: (id: UUID, regionID: Int, refreshRegionNames: Bool, task: Task<[String], Error>)?
    private let channelHydrationLock = NSLock()
    private var regionSwitchInProgress = false
    private var channelHydrationSuspended = false
    private var removeConnectionEventHandler: (() -> Void)?
    private var vfoRefreshTasks: [Int: Task<Void, Never>] = [:]
    private let channelHydrationAttempts = 2
    private let channelHydrationBatchSize = 5
    private let channelHydrationPacingNanoseconds: UInt64 = 35_000_000
    private let channelHydrationRetryBackoffNanoseconds: UInt64 = 120_000_000
    
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

    private var supportsExtendedFrequencyModeParameters: Bool {
        deviceInfo.firmwareVersion >= 137
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

    private func publishHydratedState(status: Status? = nil, regionNames: [String]? = nil) async {
        await MainActor.run {
            guard var currentState = self.state else { return }

            if let status {
                currentState.status = self.sanitizedStatus(status, fallback: currentState.status)
            }
            if let regionNames {
                currentState.regionNames = regionNames
            }

            self.state = currentState
        }
    }

    private func readChannelForHydration(_ channelID: Int) async throws -> Channel {
        var lastError: Error?

        for attempt in 1...channelHydrationAttempts {
            do {
                return try await connection.getChannel(channelID)
            } catch {
                if error is CancellationError {
                    throw error
                }

                lastError = error
                guard attempt < channelHydrationAttempts else { break }

                print("RadioController: retrying channel \(channelID) read after failure \(attempt)/\(channelHydrationAttempts): \(error)")
                try await Task.sleep(nanoseconds: channelHydrationRetryBackoffNanoseconds * UInt64(attempt))
            }
        }

        throw lastError ?? ProtocolError.invalidReply
    }

    private func withChannelHydrationLock<T>(_ body: () throws -> T) rethrows -> T {
        channelHydrationLock.lock()
        defer { channelHydrationLock.unlock() }
        return try body()
    }

    private func cancelChannelHydration() {
        vfoRefreshTasks.values.forEach { $0.cancel() }
        vfoRefreshTasks.removeAll()
        let task = withChannelHydrationLock {
            let task = channelHydrationTask?.task
            channelHydrationTask = nil
            return task
        }
        task?.cancel()
    }

    private func setChannelHydrationSuspended(_ suspended: Bool) {
        withChannelHydrationLock {
            channelHydrationSuspended = suspended
        }
    }

    private func clearChannelHydrationTask(id: UUID) {
        withChannelHydrationLock {
            if channelHydrationTask?.id == id {
                channelHydrationTask = nil
            }
        }
    }

    private func beginRegionSwitch() async throws {
        while true {
            try Task.checkCancellation()

            let activeHydration = withChannelHydrationLock {
                if regionSwitchInProgress {
                    return (isSwitching: true, task: nil as Task<[String], Error>?)
                }

                regionSwitchInProgress = true
                return (isSwitching: false, task: channelHydrationTask?.task)
            }

            if activeHydration.isSwitching {
                try await Task.sleep(nanoseconds: 50_000_000)
                continue
            }

            if let task = activeHydration.task {
                _ = try? await task.value
            }

            return
        }
    }

    private func endRegionSwitch() {
        withChannelHydrationLock {
            regionSwitchInProgress = false
        }
    }

    private func restoreRegionAfterFailedSwitch(_ regionID: Int) async -> Bool {
        do {
            try await connection.setRegion(regionID)
        } catch {
            print("RadioController: restore region \(regionID) command failed, checking status: \(error)")
        }

        try? await Task.sleep(nanoseconds: 200_000_000)

        guard let restoredStatus = await pollStatusUntilRegionMatches(regionID),
              restoredStatus.currRegion == regionID else {
            return false
        }

        await publishHydratedState(status: restoredStatus)
        return true
    }

    private func switchHardwareRegionConfirming(_ regionID: Int, restoreRegionID: Int?) async throws -> Status {
        var commandError: Error?

        do {
            try await connection.setRegion(regionID)
        } catch {
            commandError = error
        }

        try? await Task.sleep(nanoseconds: 200_000_000)

        if let confirmedStatus = await pollStatusUntilRegionMatches(regionID),
           confirmedStatus.currRegion == regionID {
            await publishHydratedState(status: confirmedStatus)
            return confirmedStatus
        }

        if let restoreRegionID, await restoreRegionAfterFailedSwitch(restoreRegionID) {
            throw commandError ?? RadioError.regionSwitchFailed
        }

        setChannelHydrationSuspended(true)
        await disconnect()
        throw commandError ?? RadioError.regionSwitchFailed
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

        await MainActor.run {
            if var currentState = self.state {
                currentState.settings = refreshedSettings
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
            setChannelHydrationSuspended(false)
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
        cancelChannelHydration()
        removeConnectionEventHandler?()
        removeConnectionEventHandler = nil
        await connection.disconnect()
        await MainActor.run {
            state = nil
            fmRadioStatus = nil
            frequencyRanges = nil
        }
        channels.removeAll()
    }

    public func handleTransportDidDisconnect() {
        backgroundHydrationTask?.cancel()
        backgroundHydrationTask = nil
        cancelChannelHydration()
        removeConnectionEventHandler?()
        removeConnectionEventHandler = nil

        Task { @MainActor in
            self.state = nil
            self.fmRadioStatus = nil
            self.frequencyRanges = nil
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

    /// Lightweight hydration for just channels and region names
    @discardableResult
    public func hydrateChannels(
        deviceInfo: DeviceInfo? = nil,
        status: Status? = nil,
        regionID: Int? = nil,
        refreshRegionNames: Bool = true,
        preserveLiveStatus: Bool? = nil
    ) async throws -> [String] {
        while true {
            try Task.checkCancellation()

            let activeDeviceInfo = deviceInfo ?? self.deviceInfo
            var activeStatus = status ?? self.status
            let currentRegion = clampedRegionID(regionID ?? activeStatus.currRegion, regionCount: activeDeviceInfo.regionCount)
            activeStatus.currRegion = currentRegion
            let shouldPreserveLiveStatus = preserveLiveStatus ?? (status == nil && regionID == nil)

            let decision = withChannelHydrationLock {
                if channelHydrationSuspended {
                    return ChannelHydrationDecision.suspended
                }

                if regionSwitchInProgress && regionID == nil {
                    return ChannelHydrationDecision.waitForRegionSwitch
                }

                if let existingHydration = channelHydrationTask {
                    let canJoinExisting = existingHydration.regionID == currentRegion &&
                        (existingHydration.refreshRegionNames || !refreshRegionNames)
                    return ChannelHydrationDecision.waitForExisting(existingHydration.task, canJoin: canJoinExisting)
                }

                let taskID = UUID()
                let task = Task { [self] in
                    try await performChannelHydration(
                        deviceInfo: activeDeviceInfo,
                        status: activeStatus,
                        regionID: currentRegion,
                        refreshRegionNames: refreshRegionNames,
                        preserveLiveStatus: shouldPreserveLiveStatus
                    )
                }
                channelHydrationTask = (
                    id: taskID,
                    regionID: currentRegion,
                    refreshRegionNames: refreshRegionNames,
                    task: task
                )
                return ChannelHydrationDecision.started(taskID, task)
            }

            switch decision {
            case .suspended:
                throw RadioError.connectionFailed
            case .waitForRegionSwitch:
                try await Task.sleep(nanoseconds: 50_000_000)
                continue
            case .waitForExisting(let existingTask, let canJoinExisting):
                if canJoinExisting {
                    return try await existingTask.value
                }

                _ = try? await existingTask.value
                continue
            case .started(let taskID, let task):
                do {
                    let regionNames = try await task.value
                    clearChannelHydrationTask(id: taskID)
                    return regionNames
                } catch {
                    clearChannelHydrationTask(id: taskID)
                    throw error
                }
            }
        }
    }

    private func performChannelHydration(
        deviceInfo activeDeviceInfo: DeviceInfo,
        status activeStatus: Status,
        regionID currentRegion: Int,
        refreshRegionNames: Bool,
        preserveLiveStatus: Bool
    ) async throws -> [String] {
        let publishStatus = preserveLiveStatus ? nil : activeStatus
        var regionDict = channels[currentRegion] ?? [:]
        let startedAt = Date()
        var loadedCount = 0
        var failedChannelIDs: [Int] = []
        var lastError: Error?
        
        // Load region memory slots
        let maxChannelsToLoad = min(30, activeDeviceInfo.channelCount)
        for i in 0..<maxChannelsToLoad {
            try Task.checkCancellation()

            do {
                let channel = try await readChannelForHydration(i)
                regionDict[channel.channelID] = channel
                channels[currentRegion] = regionDict
                loadedCount += 1

                if loadedCount == 1 || loadedCount % channelHydrationBatchSize == 0 || i == maxChannelsToLoad - 1 {
                    await publishHydratedState(status: publishStatus)
                }
            } catch {
                if error is CancellationError {
                    throw error
                }

                lastError = error
                failedChannelIDs.append(i)
                print("RadioController: failed to hydrate channel \(i): \(error)")
            }

            if i < maxChannelsToLoad - 1 {
                try await Task.sleep(nanoseconds: channelHydrationPacingNanoseconds)
            }
        }
        
        // Explicitly load VFO channels (ids 252, 251)
        for vfoID in [252, 251] {
            try Task.checkCancellation()

            do {
                let channel = try await readChannelForHydration(vfoID)
                regionDict[channel.channelID] = channel
                loadedCount += 1
            } catch {
                if error is CancellationError {
                    throw error
                }

                lastError = error
                failedChannelIDs.append(vfoID)
                print("Could not load VFO channel \(vfoID): \(error)")
            }
        }
        
        guard loadedCount > 0 || maxChannelsToLoad == 0 else {
            throw lastError ?? ProtocolError.timeout
        }

        // Store and publish before region-name reads so the UI gets useful channel rows quickly.
        channels[currentRegion] = regionDict
        await publishHydratedState(status: publishStatus)
        
        // Load regions names
        var regionNames = await MainActor.run {
            self.state?.regionNames ?? Self.placeholderRegionNames(regionCount: activeDeviceInfo.regionCount)
        }
        if refreshRegionNames && activeDeviceInfo.regionCount > 0 {
            var loadedRegionNames: [String] = []
            for i in 0..<activeDeviceInfo.regionCount {
                try Task.checkCancellation()

                do {
                    let name = try await connection.getRegionName(i)
                    loadedRegionNames.append(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Group \(i + 1)" : name)
                } catch {
                    loadedRegionNames.append("Group \(i + 1)")
                }

                try await Task.sleep(nanoseconds: 80_000_000)
            }

            if !loadedRegionNames.isEmpty {
                regionNames = loadedRegionNames
            }
        }

        if refreshRegionNames {
            await publishHydratedState(status: publishStatus, regionNames: regionNames)
        }

        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000.0)
        let failureSummary = failedChannelIDs.isEmpty ? "none" : failedChannelIDs.map(String.init).joined(separator: ",")
        print("RadioController: hydrated \(loadedCount) channels for region \(currentRegion) in \(elapsedMs)ms; failed=\(failureSummary)")
        
        return regionNames
    }

    private func startBackgroundHydration(deviceInfo: DeviceInfo, status: Status) {
        backgroundHydrationTask?.cancel()
        backgroundHydrationTask = Task { [weak self] in
            guard let self else { return }

            let startedAt = Date()

            do {
                do {
                    _ = try await self.hydrateChannels(
                        deviceInfo: deviceInfo,
                        refreshRegionNames: true,
                        preserveLiveStatus: true
                    )
                } catch {
                    guard !Task.isCancelled else { return }
                    print("RadioController: background channel hydration failed: \(error)")
                    if BLECaptureStore.isEnabled {
                        await BLECaptureStore.shared.recordNote(
                            category: "background_channel_hydration_failed",
                            message: "Radio background channel hydration failed",
                            fields: ["error": error.localizedDescription]
                        )
                    }
                }

                if Task.isCancelled { return }

                let beaconSettings = try await self.loadBeaconSettingsWithTimeout()
                if Task.isCancelled { return }

                await MainActor.run {
                    if var currentState = self.state {
                        currentState.beaconSettings = beaconSettings
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
    private func refreshSelectedVFOs(previous: Settings, current: Settings) {
        guard !isPerformingMaintenance, let state else { return }
        let region = state.status.currRegion
        let selected = [(previous.channelA, current.channelA), (previous.channelB, current.channelB)]
        for (oldID, id) in selected where [251, 252].contains(id) {
            guard oldID != id || channels[region]?[id] == nil, vfoRefreshTasks[id] == nil else { continue }
            vfoRefreshTasks[id] = Task { [weak self] in
                guard let self else { return }
                defer { if !Task.isCancelled { self.vfoRefreshTasks[id] = nil } }
                do {
                    let channel = try await self.connection.getChannel(id)
                    guard !Task.isCancelled, self.isConnected, !self.isPerformingMaintenance,
                          self.state?.status.currRegion == region, channel.channelID == id else { return }
                    self.channels[region, default: [:]][id] = channel
                    self.objectWillChange.send()
                } catch {
                    if !Task.isCancelled { print("RadioController: unable to refresh VFO \(id): \(error)") }
                }
            }
        }
    }

    private func handleEvent(_ event: EventMessage) {
        Task { @MainActor in
            guard var currentState = self.state else { return }

            switch event {
            case .statusChanged(let status):
                currentState.status = sanitizedStatus(status, fallback: currentState.status)
                self.state = currentState
            case .radioStatusChanged(let status):
                self.fmRadioStatus = status
            case .channelChanged(let channel):
                guard self.isValidChannelID(channel.channelID, deviceInfo: currentState.deviceInfo) else { return }
                self.vfoRefreshTasks.removeValue(forKey: channel.channelID)?.cancel()
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
                let previous = currentState.settings
                currentState.settings = settings
                self.state = currentState
                self.refreshSelectedVFOs(previous: previous, current: settings)
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
        guard !isPerformingMaintenance else { throw RadioMaintenanceError.operationInProgress }
        try await validateChannelForWrite(channel)
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
        guard !isPerformingMaintenance else { throw RadioMaintenanceError.operationInProgress }
        guard state != nil else {
            throw RadioError.stateNotInitialized
        }
        
        try await connection.setBeaconSettings(settings)
        
        await MainActor.run {
            guard var currentState = self.state else { return }
            currentState.beaconSettings = settings
            self.state = currentState
        }
    }

    public func getAPRSPath() async throws -> String {
        try await connection.getAPRSPath()
    }

    public func setAPRSPath(_ path: String) async throws {
        guard !isPerformingMaintenance else { throw RadioMaintenanceError.operationInProgress }
        try await connection.setAPRSPath(path)
    }
    
    /// Set settings
    public func setSettings(_ newSettings: Settings) async throws {
        guard !isPerformingMaintenance else { throw RadioMaintenanceError.operationInProgress }
        guard state != nil else {
            throw RadioError.stateNotInitialized
        }
        
        try await connection.setSettings(newSettings)
        
        await MainActor.run {
            guard var currentState = self.state else { return }
            let previous = currentState.settings
            currentState.settings = newSettings
            self.state = currentState
            self.refreshSelectedVFOs(previous: previous, current: newSettings)
        }
    }

    // MARK: - Power & Scan Commands

    @discardableResult
    public func setAudioRelayEnabled(_ enabled: Bool) async throws -> Settings {
        guard !isPerformingMaintenance else { throw RadioMaintenanceError.operationInProgress }
        guard isConnected else { throw BLEError.notConnected }
        let original = try await connection.readSettingsPayload()
        let updated = try RadioMaintenanceCodec.settingAudioRelay(enabled, in: original)
        if updated != original { try await connection.writeSettingsPayload(updated) }
        let confirmed = try await refreshSettings()
        guard confirmed.autoRelayEn == enabled else {
            throw ProtocolError.decodeError("The radio did not confirm the Audio Relay change")
        }
        return confirmed
    }

    public func setHTOnOff(_ isOn: Bool) async throws {
        guard !isPerformingMaintenance else { throw RadioMaintenanceError.operationInProgress }
        try await connection.setHTOnOff(isOn)
    }

    public func setRadioMode(_ mode: Int) async throws {
        guard !isPerformingMaintenance else { throw RadioMaintenanceError.operationInProgress }
        try await connection.setRadioMode(mode)
    }

    public func setDigitalSignalEnabled(_ isEnabled: Bool) async throws {
        try await connection.setDigitalSignalEnabled(isEnabled)
    }

    public func toggleScan() async throws {
        guard !isPerformingMaintenance else { throw RadioMaintenanceError.operationInProgress }
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
        guard !isPerformingMaintenance else { throw RadioMaintenanceError.operationInProgress }
        guard rxMHz.isFinite, txMHz.isFinite, (0..<1073.741824).contains(rxMHz), (0..<1073.741824).contains(txMHz) else {
            throw ProtocolError.decodeError("Invalid VFO frequency")
        }
        let rxHzX = UInt32(max(0, Int((rxMHz * 1_000_000.0).rounded())))
        let txHzX = UInt32(max(0, Int((txMHz * 1_000_000.0).rounded())))
        try await connection.setFreqModeParameters(
            rxFreqHzX: rxHzX,
            txFreqHzX: txHzX,
            rxSubAudio: rxSubAudio,
            txSubAudio: txSubAudio,
            mode: .satellite,
            extendedParameter: 0x61A8,
            includeExtendedParameters: supportsExtendedFrequencyModeParameters
        )
        if !supportsFrequencyScanStatusNotifications { _ = try await connection.getFreqModeStatus() }
    }

    public func setFrequencyScan(
        frequencyMHz: Double,
        mode: FrequencyMode,
        step: FrequencyScanStep,
        rxSubAudio: SubAudio?,
        txSubAudio: SubAudio?
    ) async throws {
        guard !isPerformingMaintenance else { throw RadioMaintenanceError.operationInProgress }
        guard frequencyMHz.isFinite, (0..<1073.741824).contains(frequencyMHz) else { throw ProtocolError.decodeError("Invalid scan frequency") }
        let frequencyHz = UInt32(max(0, Int((frequencyMHz * 1_000_000.0).rounded())))
        try await connection.setFreqModeParameters(
            rxFreqHzX: frequencyHz,
            txFreqHzX: frequencyHz,
            rxSubAudio: rxSubAudio,
            txSubAudio: txSubAudio,
            mode: mode,
            step: step,
            includeExtendedParameters: supportsExtendedFrequencyModeParameters
        )
    }

    public func getFrequencyScanStatus() async throws -> FrequencyModeStatus {
        try await connection.getFreqModeStatus()
    }

    public func getFrequencyRanges() async throws -> DeviceFrequencyRanges {
        let ranges = try await connection.getFrequencyRanges()
        guard deviceInfo.frequencyRangeCount == 0 || !ranges.ranges.isEmpty else {
            throw ProtocolError.decodeError("The radio returned no supported frequency bands")
        }
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
        guard !isPerformingMaintenance else { throw RadioMaintenanceError.operationInProgress }
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
        guard !isPerformingMaintenance else { throw RadioMaintenanceError.operationInProgress }
        if data.count > 330 {
            throw RadioError.dataTooLong
        }

        for fragment in TncDataFragment.fragments(for: data) {
            try await connection.sendTncDataFragment(fragment)
        }
    }
    
    /// Set region name
    public func setRegionName(_ regionID: Int, name: String) async throws {
        guard !isPerformingMaintenance else { throw RadioMaintenanceError.operationInProgress }
        guard var currentState = state else {
            throw RadioError.stateNotInitialized
        }
        
        guard regionID < currentState.deviceInfo.regionCount else {
            throw RadioError.invalidChannelID // reusing error or make new one
        }

        #if DEBUG
        let regionCount = currentState.deviceInfo.regionCount
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
                    try await beginRegionSwitch()
                    defer { endRegionSwitch() }

                    let priorRegion = await MainActor.run {
                        self.state?.status.currRegion ?? currentState.status.currRegion
                    }

                    if priorRegion != regionID {
                        _ = try await switchHardwareRegionConfirming(regionID, restoreRegionID: priorRegion)
                    }

                    do {
                        try await connection.setCurrentRegionName(name)
                    } catch {
                        if priorRegion != regionID {
                            _ = try? await switchHardwareRegionConfirming(priorRegion, restoreRegionID: nil)
                        }
                        throw error
                    }

                    if priorRegion != regionID {
                        _ = try await switchHardwareRegionConfirming(priorRegion, restoreRegionID: nil)
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

        var updatedRegionNames: [String]
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

                updatedRegionNames = afterNames
            } catch {
                print("[REGION-RENAME] Warning: failed to read names after rename: \(error)")
                var newRegions = currentState.regionNames
                if regionID < newRegions.count {
                    newRegions[regionID] = name
                }
                updatedRegionNames = newRegions
            }
        } else {
            updatedRegionNames = currentState.regionNames
        }
        #else
        // Update local state
        var newRegions = currentState.regionNames
        if regionID < newRegions.count {
            newRegions[regionID] = name
        }
        updatedRegionNames = newRegions
        #endif

        await MainActor.run {
            guard var latestState = self.state else { return }
            latestState.regionNames = updatedRegionNames
            self.state = latestState
        }
    }
    
    /// Set current region
    public func setRegion(_ regionID: Int) async throws {
        guard !isPerformingMaintenance else { throw RadioMaintenanceError.operationInProgress }
        guard let currentState = state else {
            throw RadioError.stateNotInitialized
        }
        
        guard regionID < currentState.deviceInfo.regionCount else {
            throw RadioError.invalidChannelID
        }
        
        try await beginRegionSwitch()
        defer { endRegionSwitch() }

        let restoreRegionID = await MainActor.run {
            self.state?.status.currRegion ?? currentState.status.currRegion
        }

        let updatedStatus = try await switchHardwareRegionConfirming(
            regionID,
            restoreRegionID: restoreRegionID
        )

        // Hydrate channels explicitly for the target region, independent of any delayed status event.
        _ = try await hydrateChannels(
            deviceInfo: currentState.deviceInfo,
            status: updatedStatus,
            regionID: regionID,
            refreshRegionNames: false,
            preserveLiveStatus: true
        )
    }
    
    /// Assign channel to region
    public func assignChannelToRegion(regionID: Int, channelID: Int) async throws {
        guard !isPerformingMaintenance else { throw RadioMaintenanceError.operationInProgress }
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
        guard !isPerformingMaintenance else { throw RadioMaintenanceError.operationInProgress }
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
        guard !isPerformingMaintenance else { throw RadioMaintenanceError.operationInProgress }
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

        try await validateChannelForWrite(channel)
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
        guard !isPerformingMaintenance else { throw RadioMaintenanceError.operationInProgress }
        try await connection.setPF(config)
    }

    public func getPFActionsRaw() async throws -> Data {
        try await connection.getPFActionsRaw()
    }

    public func refreshFMRadioStatus() async throws {
        guard deviceInfo.supportsRadio else { throw ProtocolError.commandFailed(.notSupported, "This radio has no FM broadcast receiver") }
        let status = try await connection.getFMRadioStatus()
        await MainActor.run { self.fmRadioStatus = status }
    }

    public func setFMRadioEnabled(_ enabled: Bool) async throws {
        guard !isPerformingMaintenance else { throw RadioMaintenanceError.operationInProgress }
        try await connection.setRadioMode(enabled ? 2 : 0)
        try await refreshFMRadioStatus()
    }

    public func tuneFMRadio(_ frequencyMHz: Double) async throws {
        guard !isPerformingMaintenance else { throw RadioMaintenanceError.operationInProgress }
        try await connection.tuneFMRadio(frequencyMHz)
        try await refreshFMRadioStatus()
    }

    public func seekFMRadio(up: Bool) async throws {
        guard !isPerformingMaintenance else { throw RadioMaintenanceError.operationInProgress }
        try await connection.seekFMRadio(up: up)
        try await refreshFMRadioStatus()
    }

    public func trustedBluetoothDevices() async throws -> [TrustedBluetoothDevice] {
        try await connection.getTrustedDevices()
    }

    public func forgetBluetoothDevice(_ device: TrustedBluetoothDevice) async throws {
        guard !isPerformingMaintenance else { throw RadioMaintenanceError.operationInProgress }
        try await connection.deleteTrustedDevice(device.address)
    }

    public func validateChannelForWrite(_ channel: Channel) async throws {
        let numericIssues = ChannelFrequencyValidator.issues(for: channel, ranges: nil)
        if !numericIssues.isEmpty { throw ProtocolError.decodeError(numericIssues.joined(separator: " ")) }
        if channel.rxFreq == 0 && channel.txFreq == 0 { return }
        var ranges = frequencyRanges
        if ranges == nil && deviceInfo.frequencyRangeCount > 0 {
            ranges = try await getFrequencyRanges()
        }
        let issues = ChannelFrequencyValidator.issues(for: channel, ranges: ranges)
        if !issues.isEmpty { throw ProtocolError.decodeError(issues.joined(separator: " ")) }
    }

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

@MainActor
extension RadioController: RadioBackupTransport {
    public func beginBackupOperation() async throws {
        guard isConnected else { throw BLEError.notConnected }
        guard !isPerformingMaintenance else { throw RadioMaintenanceError.operationInProgress }
        isPerformingMaintenance = true
        var acquiredRegion = false
        do {
            try await beginRegionSwitch()
            acquiredRegion = true
            let latestStatus = try await connection.getStatus()
            let latestSettings = try await connection.getSettings()
            guard !latestStatus.isInTx, !latestStatus.isScan, !latestSettings.scan,
                  frequencyScanStatus?.isSeeking != true else { throw RadioMaintenanceError.radioBusy }
            guard (0..<deviceInfo.regionCount).contains(latestStatus.currRegion) else { throw ProtocolError.invalidReply }
            backgroundHydrationTask?.cancel()
            setChannelHydrationSuspended(true)
        } catch {
            isPerformingMaintenance = false
            if acquiredRegion { endRegionSwitch() }
            throw error
        }
    }

    public func endBackupOperation() {
        channels.removeAll()
        setChannelHydrationSuspended(false)
        endRegionSwitch()
        isPerformingMaintenance = false
        if connection.isConnected { Task { try? await self.hydrate() } }
    }

    public func backupRegion() async throws -> Int {
        try await connection.getStatus().currRegion
    }

    public func selectBackupRegion(_ index: Int) async throws {
        if try await backupRegion() == index { return }
        try await connection.setRegion(index)
        guard await pollStatusUntilRegionMatches(index)?.currRegion == index else { throw RadioBackupError.regionRestoreFailed }
    }

    public func readBackupChannel(_ slot: Int) async throws -> Channel {
        let channel = try await readChannelForHydration(slot)
        try await Task.sleep(nanoseconds: channelHydrationPacingNanoseconds)
        return channel
    }

    public func writeBackupChannel(_ channel: Channel, region: Int?) async throws {
        if let region {
            try await connection.setRegionChannel(regionID: region, slot: channel.channelID, channel: channel)
        } else {
            try await connection.setChannel(channel)
        }
    }

    public func readBackupRegionName(_ index: Int) async throws -> String { try await connection.getRegionName(index) }
    public func writeBackupRegionName(_ name: String, index: Int) async throws { try await connection.setRegionName(index, name: name) }
    public func readBackupSettings() async throws -> Data { try await connection.readSettingsPayload() }
    public func writeBackupSettings(_ data: Data) async throws { try await connection.writeSettingsPayload(data) }
    public func writeBackupBeacon(_ data: Data) async throws { try await connection.writeBeaconSettingsPayload(data) }
    public func writeBackupPath(_ path: String) async throws { try await connection.setAPRSPath(path) }
    public func writeBackupButtons(_ config: PFConfig) async throws { try await connection.setPF(config) }

    public func validateBackupChannels(_ channels: [Channel]) async throws {
        for channel in channels { try await validateChannelForWrite(channel) }
    }

    public func readBackupBeacon() async throws -> Data? {
        do { return try await connection.readBeaconSettingsPayload() }
        catch ProtocolError.commandFailed(.notSupported, _) { return nil }
    }

    public func readBackupPath() async throws -> String? {
        do { return try await connection.getAPRSPath() }
        catch ProtocolError.commandFailed(.notSupported, _) { return nil }
    }

    public func readBackupButtons() async throws -> PFConfig? {
        do { return try await connection.getPF() }
        catch ProtocolError.commandFailed(.notSupported, _) { return nil }
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
    case regionSwitchFailed
    
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
        case .regionSwitchFailed:
            return "Radio did not confirm the requested memory group."
        }
    }
}
