//
//  RadioManager.swift
//  FieldHT
//
//  Consolidated RadioManager
//

import Foundation
import Combine
import SwiftUI

/// Manages the radio connection state and provides access to radio control
@MainActor
public class RadioManager: ObservableObject {
    // Connection State
    @Published public var radioController: RadioController?
    @Published public var isConnected: Bool = false
    @Published public var connectionError: String?
    @Published public var isConnecting: Bool = false
    @Published public var isAutoReconnecting: Bool = false
    @Published public var autoReconnectEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoReconnectEnabled, forKey: autoReconnectEnabledKey)
            if !autoReconnectEnabled {
                reconnectTask?.cancel()
                reconnectTask = nil
                isAutoReconnecting = false
            }
        }
    }
    
    // Derived Radio State (Convenience for UI Binding)
    // These properties forward values from radioController?.state
    // In a pure MVVM + ObservableObject world, views could observe radioController.state directly,
    // but exposing them here keeps the API similar to before and handles the optional controller gracefully.
    
    var vfoAIndex: Int { radioController?.state?.settings.channelA ?? 0 }
    var vfoBIndex: Int { radioController?.state?.settings.channelB ?? 0 }
    var activeRegionIndex: Int { radioController?.state?.status.currRegion ?? 0 }
    var squelchLevel: Int { radioController?.state?.settings.squelchLevel ?? 0 }
    var doubleChannel: Int { radioController?.state?.settings.doubleChannel ?? 1 }
    var vfoAFrequency: Int { radioController?.state?.settings.vfo1ModFreqX ?? 0 }
    var vfoBFrequency: Int { radioController?.state?.settings.vfo2ModFreqX ?? 0 }
    
    var channels: [Channel] { radioController?.channelsForCurrentRegion ?? [] }
    var regionNames: [String] { radioController?.regionNames ?? [] }
    
    // Channel IDs for special functions:
    // VFO A: 252
    // VFO B: 251
    // NOAA Monitoring: 253
    

    
    var isTransmitting: Bool { radioController?.state?.status.isInTx ?? false }
    var isReceiving: Bool { radioController?.state?.status.isInRx ?? false }
    var rssi: Int { Int(radioController?.state?.status.rssi ?? 0) }
    var activeChannel: ChannelType { 
        if let val = radioController?.state?.settings.doubleChannel {
            return ChannelType.fromProtocolValue(val)
        }
        return .off
    }
    var currChIDUpper: Int { radioController?.state?.status.currChIDUpper ?? 0 }
    var isScanning: Bool { radioController?.state?.settings.scan ?? false }

    
    @Published public var batteryVoltage: Double = 0.0
    @Published public var batteryLevel: Int = 0
    
    @Published public var isBusy: Bool = false
    @Published public var errorMessage: String?
    
    private var connectionTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // Reuse the underlying transport/controller across reconnect attempts to avoid
    // recreating CoreBluetooth managers repeatedly (can lead to XPC invalid loops).
    private var connectionController: RadioController?
    private var connectionControllerDeviceUUID: UUID?

    private let lastPairedDeviceKey = "com.fieldHT.lastPairedDeviceUUID"
    private let autoReconnectEnabledKey = "com.fieldHT.autoReconnectEnabled"
    private var reconnectAttempt: Int = 0

    private let maxAutoReconnectAttempts: Int = 6
    private let maxAutoReconnectTotalSeconds: TimeInterval = 90
    
    public init() {
        if UserDefaults.standard.object(forKey: autoReconnectEnabledKey) == nil {
            UserDefaults.standard.set(true, forKey: autoReconnectEnabledKey)
        }
        self.autoReconnectEnabled = UserDefaults.standard.bool(forKey: autoReconnectEnabledKey)

        if autoReconnectEnabled, let lastUUID = lastPairedDeviceUUID {
            startAutoReconnect(to: lastUUID)
        }
    }

    public var lastPairedDeviceUUID: UUID? {
        get {
            guard let uuidString = UserDefaults.standard.string(forKey: lastPairedDeviceKey),
                  let uuid = UUID(uuidString: uuidString) else {
                return nil
            }
            return uuid
        }
        set {
            if let uuid = newValue {
                UserDefaults.standard.set(uuid.uuidString, forKey: lastPairedDeviceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastPairedDeviceKey)
            }
        }
    }
    
    /// Connect to a radio device
    public func connect(to deviceUUID: UUID) {
        guard !isConnecting && !isConnected else { return }

        // A user action implies we should keep trying to stay connected.
        autoReconnectEnabled = true
        lastPairedDeviceUUID = deviceUUID
        
        isConnecting = true
        connectionError = nil

        // If an auto-reconnect loop is running, let it drive future attempts.
        reconnectTask?.cancel()
        reconnectTask = nil
        isAutoReconnecting = false
        reconnectAttempt = 0
        
        connectionTask = Task {
            do {
                if let existing = self.connectionController,
                   let existingUUID = self.connectionControllerDeviceUUID,
                   existingUUID != deviceUUID {
                    // Switching devices: tear down the prior controller before reusing state.
                    await existing.disconnect()
                    self.connectionController = nil
                    self.connectionControllerDeviceUUID = nil
                }

                let controller = self.connectionController ?? RadioController.newBLE(deviceUUID: deviceUUID, radioManager: self)
                self.connectionController = controller
                self.connectionControllerDeviceUUID = deviceUUID

                // Subscribe to changes from the controller before connecting
                subscribeToRadio(controller)

                try await controller.connect()

                self.radioController = controller
                self.isConnected = true
                self.isConnecting = false
                
                // Start polling for battery
                startPolling()
            } catch {
                if error is CancellationError {
                    self.connectionError = nil
                    self.isConnecting = false
                    self.radioController = nil
                    self.cancellables.removeAll()
                    return
                }

                self.connectionError = error.localizedDescription
                self.isConnecting = false
                self.radioController = nil
                self.cancellables.removeAll()

                startAutoReconnect(to: deviceUUID)
            }
        }
    }
    
    private func subscribeToRadio(_ radio: RadioController) {
        cancellables.removeAll()
        radio.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
            
        // Observe radio.state specifically if objectWillChange isn't enough (it should be)
        // But since we are creating derived properties, objectWillChange on RadioController
        // should signal us to update.
    }
    
    /// Disconnect from the radio
    public func disconnect() {
        // A user action implies we should stop trying to reconnect.
        autoReconnectEnabled = false

        connectionTask?.cancel()
        connectionTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        isAutoReconnecting = false
        reconnectAttempt = 0

        stopPolling()
        cancellables.removeAll()
        
        Task {
            let controller = connectionController ?? radioController
            if let controller {
                await controller.disconnect()
            }
            
            await MainActor.run {
                self.connectionController = nil
                self.connectionControllerDeviceUUID = nil
                self.radioController = nil
                self.isConnected = false
                self.connectionError = nil
            }
        }
    }

    /// Called by the BLE layer when the transport drops unexpectedly.
    /// This is intentionally lightweight and safe to call multiple times.
    public func handleTransportDidDisconnect(error: Error?) {
        // Prevent an in-flight connect task from racing with the disconnect callback.
        connectionTask?.cancel()
        connectionTask = nil

        stopPolling()
        cancellables.removeAll()

        radioController = nil
        isConnected = false
        isConnecting = false

        if let error {
            connectionError = error.localizedDescription
        }

        if autoReconnectEnabled, let uuid = lastPairedDeviceUUID {
            startAutoReconnect(to: uuid)
        }
    }

    private func startAutoReconnect(to deviceUUID: UUID) {
        guard autoReconnectEnabled else { return }
        guard !isConnected else { return }

        // Avoid multiple loops.
        if reconnectTask != nil { return }

        isAutoReconnecting = true
        reconnectAttempt = 0

        let startedAt = Date()

        reconnectTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                if !self.autoReconnectEnabled {
                    break
                }
                if self.isConnected {
                    break
                }
                if self.isConnecting {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    continue
                }

                let elapsed = Date().timeIntervalSince(startedAt)
                if self.reconnectAttempt >= self.maxAutoReconnectAttempts || elapsed >= self.maxAutoReconnectTotalSeconds {
                    self.connectionError = "Unable to reconnect. Tap Connect to try again."
                    self.isConnecting = false
                    self.radioController = nil
                    self.cancellables.removeAll()
                    // Stop the loop and persist that we're no longer auto-reconnecting.
                    self.autoReconnectEnabled = false
                    break
                }

                self.isConnecting = true
                self.connectionError = nil

                do {
                    if let existing = self.connectionController,
                       let existingUUID = self.connectionControllerDeviceUUID,
                       existingUUID != deviceUUID {
                        await existing.disconnect()
                        self.connectionController = nil
                        self.connectionControllerDeviceUUID = nil
                    }

                    let controller = self.connectionController ?? RadioController.newBLE(deviceUUID: deviceUUID, radioManager: self)
                    self.connectionController = controller
                    self.connectionControllerDeviceUUID = deviceUUID

                    self.subscribeToRadio(controller)
                    try await controller.connect()

                    self.radioController = controller
                    self.isConnected = true
                    self.isConnecting = false
                    self.isAutoReconnecting = false
                    self.reconnectAttempt = 0
                    self.startPolling()
                    break
                } catch {
                    if error is CancellationError || Task.isCancelled {
                        break
                    }

                    self.radioController = nil
                    self.isConnected = false
                    self.isConnecting = false
                    self.cancellables.removeAll()

                    self.connectionError = error.localizedDescription

                    // If Bluetooth is unavailable, don't keep spinning.
                    if let bleError = error as? BLEError, bleError == .bluetoothUnavailable {
                        self.isConnecting = false
                        self.radioController = nil
                        self.cancellables.removeAll()
                        self.autoReconnectEnabled = false
                        break
                    }

                    let delaySeconds = self.nextReconnectDelaySeconds(attempt: self.reconnectAttempt)
                    self.reconnectAttempt += 1
                    try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                }
            }

            await MainActor.run {
                self.reconnectTask = nil
                self.isAutoReconnecting = false
            }
        }
    }

    private func nextReconnectDelaySeconds(attempt: Int) -> Double {
        // Exponential backoff with jitter, capped.
        let base = min(pow(2.0, Double(min(attempt, 6))), 60.0) // 1,2,4,8,16,32,60...
        let jitter = Double.random(in: 0...(base * 0.2))
        return max(1.0, base + jitter)
    }
    
    // MARK: - Polling
    
    private func startPolling() {
        stopPolling()
        // Poll every 60 seconds for Battery
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await self?.refreshBattery()
            }
        }
        
        // Initial fetch
        Task { try? await refreshBattery() }
    }
    
    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
    
    private func refreshBattery() async throws {
        guard let controller = radioController else { return }
        // Battery info isn't part of the main state struct usually, unless we add it to status
        // So we keep fetching it explicitly.
        let volts = try await controller.batteryVoltage()
        let level = try await controller.batteryLevelAsPercentage()
        self.batteryVoltage = volts
        self.batteryLevel = level
    }
    
    // MARK: - Actions
    
    var isDualWatchOn: Bool {
        return doubleChannel != ChannelType.off.toProtocolValue()
    }

    func setDualWatch(_ isOn: Bool) {
        let newValue: ChannelType = isOn ? .a : .off
        guard let controller = radioController, var settings = controller.state?.settings else {
            print("RadioManager: No controller or state!")
            return
        }
        isBusy = true
        Task {
            do {
                settings.doubleChannel = newValue.toProtocolValue()
                try await controller.setSettings(settings)
                print("RadioManager: Squelch set doubleChannel")
                isBusy = false
            } catch {
                print("RadioManager: Failed to set doubleChannel: \(error)")
                errorMessage = "Failed to set doubleChannel: \(error.localizedDescription)"
                isBusy = false
            }
        }
    }
    
    // MARK: - Scanning Control
    
    public func toggleScan() {
        print("RadioManager: toggleScan()")
        guard let controller = radioController else {
            print("RadioManager: No controller!")
            return
        }
        isBusy = true
        Task {
            do {
                try await controller.toggleScan()
                print("RadioManager: Scan toggled successfully")
                isBusy = false
            } catch {
                print("RadioManager: Failed to toggle scan: \(error)")
                errorMessage = "Failed to toggle scan: \(error.localizedDescription)"
                isBusy = false
            }
        }
    }
    
    // MARK: - Radio Control Actions
    
    public func setChannelA(_ index: Int) {
        print("RadioManager: setChannelA(\(index))")
        guard let controller = radioController, var settings = controller.state?.settings else {
            print("RadioManager: No controller or state!")
            return
        }
        isBusy = true
        Task {
            do {
                settings.channelA = index
                try await controller.setSettings(settings)
                print("RadioManager: Channel A set successfully")
                isBusy = false
            } catch {
                print("RadioManager: Failed to set Channel A: \(error)")
                errorMessage = "Failed to set Channel A: \(error.localizedDescription)"
                isBusy = false
            }
        }
    }
    
    public func setChannelB(_ index: Int) {
        guard let controller = radioController, var settings = controller.state?.settings else { return }
        isBusy = true
        Task {
            do {
                settings.channelB = index
                try await controller.setSettings(settings)
                isBusy = false
            } catch {
                errorMessage = "Failed to set Channel B: \(error.localizedDescription)"
                isBusy = false
            }
        }
    }
    
    public func setRegion(_ index: Int) {
        guard let controller = radioController else { return }
        isBusy = true
        Task {
            do {
                try await controller.setRegion(index)
                isBusy = false
            } catch {
                errorMessage = "Failed to set Region: \(error.localizedDescription)"
                isBusy = false
            }
        }
    }
    
    public func setSquelch(_ level: Int) {
        print("RadioManager: setSquelch(\(level))")
        guard let controller = radioController, var settings = controller.state?.settings else {
            print("RadioManager: No controller or state!")
            return
        }
        isBusy = true
        Task {
            do {
                settings.squelchLevel = level
                try await controller.setSettings(settings)
                print("RadioManager: Squelch set successfully")
                isBusy = false
            } catch {
                print("RadioManager: Failed to set Squelch: \(error)")
                errorMessage = "Failed to set Squelch: \(error.localizedDescription)"
                isBusy = false
            }
        }
    }

    // MARK: - Volume Control

    /// Get current volume level
    public func getVolume() async -> Int {
        guard let controller = radioController else { return 0 }
        do {
            return try await controller.volume()
        } catch {
            print("RadioManager: Failed to get volume: \(error)")
            return 0
        }
    }

    /// Set volume level (0-100)
    public func setVolume(_ level: Int) {
        guard let controller = radioController else { return }
        Task {
            do {
                try await controller.setVolume(level)
                print("RadioManager: Volume set to \(level)")
            } catch {
                print("RadioManager: Failed to set volume: \(error)")
                errorMessage = "Failed to set volume: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - VFO Control
    
    /// Check if VFO mode is active for channel A
    var isVFOA: Bool {
        return vfoAIndex >= 250 // Assuming 250+ is special/VFO
    }
    
    /// Check if VFO mode is active for channel B
    var isVFOB: Bool {
         return vfoBIndex >= 250
    }
    
    /// Toggle VFO mode for a channel
    public func toggleVFO(for channel: ChannelType) {
        let vfoIndex = 252 // VFO A
        
        if channel == .a {
            if isVFOA {
                setChannelA(0) 
            } else {
                setChannelA(vfoIndex)
            }
        } else if channel == .b {
             if isVFOB {
                setChannelB(0)
            } else {
                setChannelB(vfoIndex - 1) // confirmed on 251
            }
        }
    }
    
    /// Get calculated VFO Frequency in MHz
    var vfoAFrequencyMHz: Double {
        return radioController?.channelsForCurrentRegion.first(where: { $0.channelID == 252 })?.rxFreq ?? 0.0
    }
    
    var vfoBFrequencyMHz: Double {
        return radioController?.channelsForCurrentRegion.first(where: { $0.channelID == 251 })?.rxFreq ?? 0.0
    }

    /// Get VFO A Channel object
    var vfoAChannel: Channel? {
        return radioController?.channelsForCurrentRegion.first(where: { $0.channelID == 252 })
    }

    /// Get VFO B Channel object
    var vfoBChannel: Channel? {
        return radioController?.channelsForCurrentRegion.first(where: { $0.channelID == 251 })
    }
    
    /// Set frequency for VFO
    public func setFrequency(_ frequency: Double, for channel: ChannelType) {
        guard let controller = radioController else { return }
        
        let vfoID = channel == .a ? 252 : 251
        print("RadioManager: Setting VFO Freq \(frequency) MHz for channel ID \(vfoID)")
        
        isBusy = true
        Task {
            do {
                try await controller.setChannel(vfoID, txFreq: frequency, rxFreq: frequency)
                print("RadioManager: VFO Frequency set successfully")
                isBusy = false
            } catch {
                print("Failed to set VFO frequency: \(error)")
                errorMessage = "Failed to set VFO frequency: \(error.localizedDescription)"
                isBusy = false
            }
        }
    }

    public func setSplitFrequency(rxMHz: Double, txMHz: Double, for channel: ChannelType) {
        guard let controller = radioController else { return }

        let vfoID = channel == .a ? 252 : 251
        isBusy = true
        Task {
            do {
                try await controller.setChannel(vfoID, txFreq: txMHz, rxFreq: rxMHz)
                isBusy = false
            } catch {
                errorMessage = "Failed to set VFO split frequency: \(error.localizedDescription)"
                isBusy = false
            }
        }
    }

    public func setSplitFrequencyAndCTCSS(
        rxMHz: Double,
        txMHz: Double,
        rxCTCSSHz: Double?,
        txCTCSSHz: Double?,
        for channel: ChannelType
    ) {
        #if DEBUG
        // Intentionally quiet: this can be called at high frequency.
        #endif
        guard let controller = radioController else { return }

        let vfoID = channel == .a ? 252 : 251
        isBusy = true
        Task {
            do {
                // Prefer updating the full channel to preserve existing settings.
                let existing = controller.channelsForCurrentRegion.first(where: { $0.channelID == vfoID })
                var ch = existing ?? Channel.empty(channelID: vfoID)
                if existing == nil {
                    // If we didn't have a hydrated VFO channel, default to HIGH power instead of
                    // unintentionally forcing LOW by using Channel.empty().
                    ch.txAtMaxPower = true
                    ch.txAtMedPower = false
                    ch.fixedTxPower = false
                }
                ch.rxFreq = rxMHz
                ch.txFreq = txMHz
                ch.rxSubAudio = rxCTCSSHz.map { .frequency($0) }
                ch.txSubAudio = txCTCSSHz.map { .frequency($0) }
                #if DEBUG
                // Intentionally quiet: avoid noisy debug logs.
                #endif
                try await controller.setChannel(ch)

                #if DEBUG
                // Only verify-readback when we are actually trying to apply a tone.
                if (rxCTCSSHz ?? -1) > 0 || (txCTCSSHz ?? -1) > 0 {
                    if let verified = controller.channelsForCurrentRegion.first(where: { $0.channelID == vfoID }) {
                        // Intentionally quiet: avoid noisy debug logs.
                    } else {
                        // Intentionally quiet: avoid noisy debug logs.
                    }
                }
                #endif
                isBusy = false
            } catch {
                errorMessage = "Failed to set VFO tones: \(error.localizedDescription)"
                isBusy = false
            }
        }
    }
    
    public func switchActiveChannel(to channel: ChannelType) {
        print("RadioManager: switchActiveChannel(\(channel))")
        guard let controller = radioController, var settings = controller.state?.settings else {
            print("RadioManager: No controller or state!")
            return
        }
        isBusy = true
        Task {
            do {
                settings.doubleChannel = channel.toProtocolValue()
                try await controller.setSettings(settings)
                // The activeChannel derived property will update automatically when state changes
                print("RadioManager: Active channel switched to \(channel)")
                isBusy = false
            } catch {
                print("RadioManager: Failed to switch channel: \(error)")
                errorMessage = "Failed to switch channel: \(error.localizedDescription)"
                isBusy = false
            }
        }
    }
    public func updateChannel(_ channel: Channel) {
        guard let controller = radioController else { return }
        isBusy = true
        Task {
            do {
                try await controller.setChannel(channel)
                isBusy = false
            } catch {
                errorMessage = "Failed to update channel: \(error.localizedDescription)"
                isBusy = false
            }
        }
    }

    // MARK: - Satellite mode (reverse-engineered)

    public func setFreqModeParameters(
        rxMHz: Double,
        txMHz: Double,
        rxCTCSSHz: Double? = nil,
        txCTCSSHz: Double? = nil
    ) {
        guard let controller = radioController else { return }
        Task {
            do {
                let rxTone = rxCTCSSHz.map { SubAudio.frequency($0) }
                let txTone = txCTCSSHz.map { SubAudio.frequency($0) }
                try await controller.setFreqModeParameters(
                    rxMHz: rxMHz,
                    txMHz: txMHz,
                    rxSubAudio: rxTone,
                    txSubAudio: txTone
                )
            } catch {
                print("Failed to set freq mode parameters: \(error)")
            }
        }
    }

    public func setSatModeInfo(
        name: String,
        rangeKm: Double,
        dopplerShiftHz: Int,
        azimuthDeg: Double,
        elevationDeg: Double,
        altitudeKm: Double
    ) {
        guard let controller = radioController else { return }
        Task {
            do {
                try await controller.setSatModeInfo(
                    name: name,
                    rangeKm: rangeKm,
                    dopplerShiftHz: dopplerShiftHz,
                    azimuthDeg: azimuthDeg,
                    elevationDeg: elevationDeg,
                    altitudeKm: altitudeKm
                )
            } catch {
                print("Failed to set satellite mode info: \(error)")
            }
        }
    }

    // MARK: - Beacon Settings

    /// Get beacon settings from radio
    public func getBeaconSettings() async throws -> BeaconSettings {
        guard let controller = radioController else {
            throw RadioError.stateNotInitialized
        }
        return try await controller.getBeaconSettings()
    }

    /// Set beacon settings on radio
    public func setBeaconSettings(_ settings: BeaconSettings) async throws {
        guard let controller = radioController else {
            throw RadioError.stateNotInitialized
        }
        try await controller.setBeaconSettings(settings)
    }
}
