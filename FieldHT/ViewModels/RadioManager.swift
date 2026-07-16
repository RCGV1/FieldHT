//
//  RadioManager.swift
//  FieldHT
//
//  Consolidated RadioManager
//

import Foundation
import Combine
import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// Manages the radio connection state and provides access to radio control
@MainActor
public class RadioManager: ObservableObject {
    // Connection State
    @Published public var radioController: RadioController?
    @Published public var speakerMicController: SpeakerMicController?
    @Published public var isConnected: Bool = false
    @Published public var connectionError: String?
    @Published public var isConnecting: Bool = false
    @Published public var isSpeakerMicConnecting: Bool = false
    @Published public var speakerMicConnectionError: String?
    @Published public var isAutoReconnecting: Bool = false
    @Published public var autoReconnectEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoReconnectEnabled, forKey: autoReconnectEnabledKey)
            if !autoReconnectEnabled {
                reconnectTask?.cancel()
                reconnectTask = nil
                isAutoReconnecting = false
                updateIdleTimerForCapture()
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
    var currentStatus: Status? { radioController?.state?.status }
    private var hasValidRadioReportedSpeakerMicBattery: Bool { (1...100).contains(hmBatteryLevel) }
    var supportsSpeakerMicAccessory: Bool {
        (radioController?.deviceInfo.hasHandMicrophoneSpeaker ?? false) ||
        speakerMicController != nil ||
        lastSpeakerMicDeviceUUID != nil ||
        speakerMicEvidenceIsFresh ||
        hasValidRadioReportedSpeakerMicBattery
    }
    var isSpeakerMicConnected: Bool {
        (speakerMicController?.isConnected ?? false) ||
        speakerMicEvidenceIsFresh ||
        hasValidRadioReportedSpeakerMicBattery ||
        (currentStatus?.isAOCConnected ?? false)
    }
    var isBluetoothAudioConnected: Bool { currentStatus?.isHFPConnected ?? false }
    var speakerMicBatteryPercent: Int {
        let directBattery = speakerMicController?.batteryPercent ?? 0
        if (1...100).contains(directBattery) {
            return directBattery
        }
        return hasValidRadioReportedSpeakerMicBattery ? hmBatteryLevel : 0
    }
    
    // Channel IDs for special functions:
    // VFO A: 252
    // VFO B: 251
    // NOAA Monitoring: 253
    

    
    var isTransmitting: Bool { radioController?.state?.status.isInTx ?? false }
    var isReceiving: Bool { radioController?.state?.status.isInRx ?? false }
    var rssi: Int { Int(radioController?.state?.status.rssi ?? 0) }
    var currentReceivingChannelID: Int? {
        guard isReceiving, let status = currentStatus else { return nil }

        let channelID = status.currChID
        if channelID >= 0 {
            return channelID
        }

        return nil
    }
    var activeChannel: ChannelType { 
        if let val = radioController?.state?.settings.doubleChannel {
            return ChannelType.fromProtocolValue(val)
        }
        return .off
    }
    var currChIDUpper: Int { radioController?.state?.status.currChIDUpper ?? 0 }
    var isScanning: Bool {
        if let scanStateOverride {
            return scanStateOverride
        }
        if let settingsScan = radioController?.state?.settings.scan {
            return settingsScan
        }
        return radioController?.state?.status.isScan ?? false
    }

    var effectiveMonitorMode: ChannelType {
        if isScanning {
            return .off
        }
        if let val = radioController?.state?.settings.doubleChannel {
            return ChannelType.fromProtocolValue(val)
        }
        return .off
    }

    var monitorModeLabel: String {
        if isScanning {
            return "Scanning"
        }
        return isDualWatchOn ? "Dual Monitor" : "Single Watch"
    }

    var monitorModeSystemImage: String {
        if isScanning {
            return "dot.radiowaves.left.and.right"
        }
        return isDualWatchOn ? "rectangle.split.2x1.fill" : "rectangle"
    }

    
    @Published public var batteryVoltage: Double = 0.0
    @Published public var batteryLevel: Int = 0
    @Published public var hmBatteryLevel: Int = 0
    @Published private var scanStateOverride: Bool?
    private var hasNotifiedLowBattery = false
    private var lastSpeakerMicEvidenceAt: Date?
    private var scanReturnDoubleChannel: Int?
    private var lastMemoryChannelAIndex: Int?
    private var lastMemoryChannelBIndex: Int?
    
    @Published public var isBusy: Bool = false
    @Published public var errorMessage: String?
    
    private var connectionTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var connectionHealthTask: Task<Void, Never>?
    private var radioPollTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var lastRadioBatteryRefreshAt: Date?

    // Reuse the underlying transport/controller across reconnect attempts to avoid
    // recreating CoreBluetooth managers repeatedly (can lead to XPC invalid loops).
    private var connectionController: RadioController?
    private var connectionControllerDeviceUUID: UUID?

    private let lastPairedDeviceKey = "com.fieldHT.lastPairedDeviceUUID"
    private let lastSpeakerMicDeviceKey = "com.fieldHT.lastSpeakerMicDeviceUUID"
    private let autoReconnectEnabledKey = "com.fieldHT.autoReconnectEnabled"
    private var reconnectAttempt: Int = 0

    private let maxAutoReconnectDelaySeconds: Double = 15
    private let speakerMicEvidenceTimeout: TimeInterval = 90
    private let normalRadioPollInterval: TimeInterval = 60
    private let speakerMicQuietRadioPollInterval: TimeInterval = 300
    
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

    public var lastSpeakerMicDeviceUUID: UUID? {
        get {
            guard let uuidString = UserDefaults.standard.string(forKey: lastSpeakerMicDeviceKey),
                  let uuid = UUID(uuidString: uuidString) else {
                return nil
            }
            return uuid
        }
        set {
            if let uuid = newValue {
                UserDefaults.standard.set(uuid.uuidString, forKey: lastSpeakerMicDeviceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastSpeakerMicDeviceKey)
            }
        }
    }

    public func forgetLastPairedRadio() {
        let savedUUID = lastPairedDeviceUUID

        autoReconnectEnabled = false
        reconnectTask?.cancel()
        reconnectTask = nil
        isAutoReconnecting = false
        reconnectAttempt = 0
        lastPairedDeviceUUID = nil

        guard savedUUID == connectionControllerDeviceUUID else {
            return
        }

        disconnect()
    }

    private func recordConnectionNote(category: String, message: String, fields: [String: String] = [:]) {
        guard BLECaptureStore.isEnabled else { return }
        Task {
            await BLECaptureStore.shared.recordNote(category: category, message: message, fields: fields)
        }
    }

    private func updateIdleTimerForCapture() {
        #if DEBUG && canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled =
            BLECaptureStore.isEnabled &&
            (isConnected || isConnecting || isAutoReconnecting)
        #endif
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
        updateIdleTimerForCapture()

        let startedAt = Date()
        recordConnectionNote(category: "radio_connect_requested", message: "User requested radio connection", fields: [
            "device_uuid": deviceUUID.uuidString
        ])
        
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
                self.connectionError = nil
                self.updateIdleTimerForCapture()
                self.recordConnectionNote(category: "radio_connect_completed", message: "Radio connected", fields: [
                    "device_uuid": deviceUUID.uuidString,
                    "elapsed_ms": String(Int(Date().timeIntervalSince(startedAt) * 1000.0))
                ])
                
                // Start polling for battery. Speaker-mic direct BLE is manual-only for now;
                // auto-restoring that second link was causing connection churn.
                startPolling()
            } catch {
                if error is CancellationError {
                    self.connectionError = nil
                    self.isConnecting = false
                    self.radioController = nil
                    self.cancellables.removeAll()
                    self.updateIdleTimerForCapture()
                    return
                }

                self.connectionError = error.localizedDescription
                self.isConnecting = false
                self.radioController = nil
                self.cancellables.removeAll()
                self.updateIdleTimerForCapture()
                self.recordConnectionNote(category: "radio_connect_failed", message: "Radio connection failed", fields: [
                    "device_uuid": deviceUUID.uuidString,
                    "elapsed_ms": String(Int(Date().timeIntervalSince(startedAt) * 1000.0)),
                    "error": error.localizedDescription
                ])

                startAutoReconnect(to: deviceUUID)
            }
        }
    }
    
    private func subscribeToRadio(_ radio: RadioController) {
        cancellables.removeAll()
        radio.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                if let override = self?.scanStateOverride {
                    let reportedScan =
                        radio.state?.settings.scan ??
                        radio.state?.status.isScan
                    if reportedScan == override {
                        self?.scanStateOverride = nil
                    }
                }
                self?.refreshSpeakerMicEvidenceFromStatus()
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
        stopConnectionHealthLogging()

        stopPolling()
        cancellables.removeAll()
        
        Task {
            let controller = connectionController ?? radioController
            if let controller {
                await controller.disconnect()
            }

            if let accessory = self.speakerMicController {
                await accessory.disconnect()
            }
            
            await MainActor.run {
                // Keep the main controller alive so a manual reconnect uses the same
                // CBCentralManager instead of recreating it in a transient state.
                self.radioController = nil
                self.speakerMicController = nil
                self.isConnected = false
                self.isConnecting = false
                self.connectionError = nil
                self.speakerMicConnectionError = nil
                self.isSpeakerMicConnecting = false
                self.hmBatteryLevel = 0
                self.lastSpeakerMicEvidenceAt = nil
                self.scanStateOverride = nil
                self.scanReturnDoubleChannel = nil
                self.lastMemoryChannelAIndex = nil
                self.lastMemoryChannelBIndex = nil
                self.updateIdleTimerForCapture()
            }
        }
    }

    /// Called by the BLE layer when the transport drops unexpectedly.
    /// This is intentionally lightweight and safe to call multiple times.
    public func handleTransportDidDisconnect(error: Error?) {
        let status = currentStatus
        print(
            "RadioManager: transport disconnected " +
            "error=\(error?.localizedDescription ?? "nil") " +
            "aoc=\(status?.isAOCConnected ?? false) " +
            "hfp=\(status?.isHFPConnected ?? false) " +
            "tx=\(status?.isInTx ?? false) " +
            "rx=\(status?.isInRx ?? false)"
        )
        // Prevent an in-flight connect task from racing with the disconnect callback.
        connectionTask?.cancel()
        connectionTask = nil

        stopPolling()
        stopConnectionHealthLogging()
        cancellables.removeAll()

        connectionController?.handleTransportDidDisconnect()
        radioController = nil
        isConnected = false
        isConnecting = false
        isSpeakerMicConnecting = false
        updateIdleTimerForCapture()
        scanStateOverride = nil
        scanReturnDoubleChannel = nil
        lastMemoryChannelAIndex = nil
        lastMemoryChannelBIndex = nil

        if let error {
            connectionError = error.localizedDescription
        }

        recordConnectionNote(category: "radio_transport_disconnected", message: "Radio transport disconnected", fields: [
            "device_uuid": connectionControllerDeviceUUID?.uuidString ?? lastPairedDeviceUUID?.uuidString ?? "unknown",
            "error": error?.localizedDescription ?? "nil"
        ])

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
        connectionError = "Connection lost. Reconnecting..."
        updateIdleTimerForCapture()
        recordConnectionNote(category: "radio_reconnect_started", message: "Started auto reconnect loop", fields: [
            "device_uuid": deviceUUID.uuidString
        ])

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

                self.isConnecting = true
                self.connectionError = "Connection lost. Reconnecting..."
                self.updateIdleTimerForCapture()
                self.recordConnectionNote(category: "radio_reconnect_attempt", message: "Attempting radio reconnect", fields: [
                    "device_uuid": deviceUUID.uuidString,
                    "attempt": String(self.reconnectAttempt + 1)
                ])

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
                    self.connectionError = nil
                    self.updateIdleTimerForCapture()
                    self.recordConnectionNote(category: "radio_reconnect_completed", message: "Radio reconnect succeeded", fields: [
                        "device_uuid": deviceUUID.uuidString
                    ])
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
                    self.updateIdleTimerForCapture()

                    self.connectionError = "Connection lost. Reconnecting..."

                    // If Bluetooth is unavailable, don't keep spinning.
                    if let bleError = error as? BLEError, bleError == .bluetoothUnavailable {
                        self.isConnecting = false
                        self.radioController = nil
                        self.cancellables.removeAll()
                        self.autoReconnectEnabled = false
                        self.connectionError = error.localizedDescription
                        self.updateIdleTimerForCapture()
                        self.recordConnectionNote(category: "radio_reconnect_stopped", message: "Stopped auto reconnect because Bluetooth is unavailable", fields: [
                            "device_uuid": deviceUUID.uuidString,
                            "error": error.localizedDescription
                        ])
                        break
                    }

                    let delaySeconds = self.nextReconnectDelaySeconds(attempt: self.reconnectAttempt)
                    self.recordConnectionNote(category: "radio_reconnect_retry_scheduled", message: "Scheduling next radio reconnect attempt", fields: [
                        "device_uuid": deviceUUID.uuidString,
                        "attempt": String(self.reconnectAttempt + 1),
                        "delay_seconds": String(format: "%.2f", delaySeconds),
                        "error": error.localizedDescription
                    ])
                    self.reconnectAttempt += 1
                    try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                }
            }

            await MainActor.run {
                self.reconnectTask = nil
                self.isAutoReconnecting = false
                self.updateIdleTimerForCapture()
            }
        }
    }

    private func nextReconnectDelaySeconds(attempt: Int) -> Double {
        let schedule: [Double] = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, maxAutoReconnectDelaySeconds]
        let index = min(attempt, schedule.count - 1)
        let base = schedule[index]
        let jitter = Double.random(in: 0...(base * 0.15))
        return min(maxAutoReconnectDelaySeconds, base + jitter)
    }

    private var speakerMicEvidenceIsFresh: Bool {
        guard let lastSpeakerMicEvidenceAt else { return false }
        return Date().timeIntervalSince(lastSpeakerMicEvidenceAt) < speakerMicEvidenceTimeout
    }

    private func noteSpeakerMicEvidence() {
        lastSpeakerMicEvidenceAt = Date()
    }

    private func refreshSpeakerMicEvidenceFromStatus() {
        if currentStatus?.isAOCConnected == true {
            noteSpeakerMicEvidence()
        }

        if !speakerMicEvidenceIsFresh && currentStatus?.isAOCConnected != true && hmBatteryLevel <= 0 {
            objectWillChange.send()
        }
    }

    public func connectSpeakerMic(to deviceUUID: UUID) {
        guard !isSpeakerMicConnecting else { return }

        isSpeakerMicConnecting = true
        speakerMicConnectionError = nil

        Task {
            do {
                if let existing = self.speakerMicController, existing.deviceUUID != deviceUUID {
                    await existing.disconnect()
                    self.speakerMicController = nil
                }

                let controller = self.speakerMicController ?? SpeakerMicController.newBLE(deviceUUID: deviceUUID)
                try await controller.connect()

                await MainActor.run {
                    self.speakerMicController = controller
                    self.lastSpeakerMicDeviceUUID = deviceUUID
                    self.isSpeakerMicConnecting = false
                    self.speakerMicConnectionError = nil
                    self.noteSpeakerMicEvidence()
                }
            } catch {
                await MainActor.run {
                    self.speakerMicController = nil
                    self.isSpeakerMicConnecting = false
                    self.speakerMicConnectionError = error.localizedDescription
                }
            }
        }
    }

    public func disconnectSpeakerMic() {
        Task {
            if let controller = self.speakerMicController {
                await controller.disconnect()
            }

            await MainActor.run {
                self.speakerMicController = nil
                self.isSpeakerMicConnecting = false
                self.speakerMicConnectionError = nil
            }
        }
    }
    
    // MARK: - Polling
    
    private func startPolling() {
        stopPolling()
        startConnectionHealthLogging()
        radioPollTask = Task { [weak self] in
            await self?.runRadioBatteryPollLoop()
        }
    }
    
    private func stopPolling() {
        radioPollTask?.cancel()
        radioPollTask = nil
    }

    private var shouldReduceRadioPollingForSpeakerMic: Bool {
        (speakerMicController?.isConnected ?? false) ||
        speakerMicEvidenceIsFresh ||
        (currentStatus?.isAOCConnected ?? false) ||
        (currentStatus?.isHFPConnected ?? false)
    }

    private var currentRadioPollInterval: TimeInterval {
        shouldReduceRadioPollingForSpeakerMic ? speakerMicQuietRadioPollInterval : normalRadioPollInterval
    }

    private func runRadioBatteryPollLoop() async {
        await performRadioBatteryPollIfNeeded(reason: "initial")

        while !Task.isCancelled {
            let interval = currentRadioPollInterval
            let nanoseconds = UInt64(interval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await performRadioBatteryPollIfNeeded(reason: "periodic")
        }
    }

    private func performRadioBatteryPollIfNeeded(reason: String) async {
        guard radioController != nil else { return }

        let quietMode = shouldReduceRadioPollingForSpeakerMic
        if quietMode {
            let now = Date()
            if let lastRadioBatteryRefreshAt,
               now.timeIntervalSince(lastRadioBatteryRefreshAt) < speakerMicQuietRadioPollInterval {
                recordConnectionNote(category: "radio_poll_quiet_skip", message: "Skipped radio poll during speaker mic quiet mode", fields: [
                    "reason": reason,
                    "quiet_interval_seconds": String(Int(speakerMicQuietRadioPollInterval)),
                    "last_refresh_age_seconds": String(Int(now.timeIntervalSince(lastRadioBatteryRefreshAt)))
                ])
                return
            }
        }

        do {
            try await refreshBattery(
                includeVoltage: !quietMode,
                includeSpeakerMicBattery: !quietMode,
                reason: reason,
                quietMode: quietMode
            )
        } catch {
            recordConnectionNote(category: "radio_poll_failed", message: "Radio battery poll failed", fields: [
                "reason": reason,
                "quiet_mode": String(quietMode),
                "error": error.localizedDescription
            ])
        }
    }

    private func startConnectionHealthLogging() {
        stopConnectionHealthLogging()

        guard let uuid = lastPairedDeviceUUID else { return }
        let startedAt = Date()
        recordConnectionNote(category: "connection_health_started", message: "Started connection health logging", fields: [
            "device_uuid": uuid.uuidString
        ])

        connectionHealthTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                guard self.isConnected, let controller = self.radioController else {
                    break
                }

                let uptimeMs = Int(Date().timeIntervalSince(startedAt) * 1000.0)
                let status = controller.state?.status
                self.recordConnectionNote(category: "connection_health", message: "Radio connection health heartbeat", fields: [
                    "device_uuid": uuid.uuidString,
                    "uptime_ms": String(uptimeMs),
                    "transport_ready": String(controller.isConnected),
                    "scan": String(controller.state?.settings.scan ?? false),
                    "rx": String(status?.isInRx ?? false),
                    "tx": String(status?.isInTx ?? false),
                    "rssi": String(Int(status?.rssi ?? 0))
                ])

                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    private func stopConnectionHealthLogging() {
        connectionHealthTask?.cancel()
        connectionHealthTask = nil
    }
    
    private func refreshBattery(
        includeVoltage: Bool,
        includeSpeakerMicBattery: Bool,
        reason: String,
        quietMode: Bool
    ) async throws {
        guard let controller = radioController else { return }
        if includeVoltage {
            let volts = try await controller.batteryVoltage()
            self.batteryVoltage = volts
        }
        let level = try await controller.batteryLevelAsPercentage()
        self.batteryLevel = level
        self.lastRadioBatteryRefreshAt = Date()

        if currentStatus?.isAOCConnected == true {
            noteSpeakerMicEvidence()
        }

        // The live AOC status bit appears noisy on some radios, so keep trying the
        // accessory battery read while we have recent evidence the speaker mic exists.
        if includeSpeakerMicBattery && (supportsSpeakerMicAccessory || speakerMicEvidenceIsFresh || hasValidRadioReportedSpeakerMicBattery) {
            if let hmLevel = try? await controller.rcBatteryLevel(), (1...100).contains(hmLevel) {
                self.hmBatteryLevel = hmLevel
                noteSpeakerMicEvidence()
            } else if !speakerMicEvidenceIsFresh && currentStatus?.isAOCConnected != true {
                self.hmBatteryLevel = 0
            }
        }

        recordConnectionNote(category: "radio_poll_completed", message: "Radio battery poll completed", fields: [
            "reason": reason,
            "quiet_mode": String(quietMode),
            "include_voltage": String(includeVoltage),
            "include_speaker_mic_battery": String(includeSpeakerMicBattery)
        ])

        // Fire a low-battery notification once when crossing below 10%.
        // Reset the flag when the battery recovers above 15% (e.g. plugged in).
        if level > 15 {
            hasNotifiedLowBattery = false
        } else if level <= 10 && level > 0 && !hasNotifiedLowBattery {
            hasNotifiedLowBattery = true
            print("RadioManager: low battery threshold reached at \(level)%")
            NotificationManager.shared.scheduleLowBatteryNotification(level: level)
        }
    }

    /// Enable low power (power saving) mode on the radio.
    public func enableLowPowerMode() {
        guard let controller = radioController else {
            print("RadioManager: enableLowPowerMode ignored because radio is not connected")
            errorMessage = "Radio is not connected."
            return
        }
        print("RadioManager: enabling low power mode")
        isBusy = true
        Task {
            do {
                guard var settings = controller.state?.settings else {
                    throw NSError(
                        domain: "FieldHT.RadioManager",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Radio settings are unavailable."]
                    )
                }
                if settings.powerSavingMode {
                    print("RadioManager: low power mode already enabled")
                    await MainActor.run {
                        self.isBusy = false
                    }
                    return
                }
                settings.powerSavingMode = true
                try await controller.setSettings(settings)
                print("RadioManager: low power mode enabled successfully")
                await MainActor.run {
                    self.isBusy = false
                }
            } catch {
                print("RadioManager: failed to enable low power mode: \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = "Failed to enable low power mode: \(error.localizedDescription)"
                    self.isBusy = false
                }
            }
        }
    }
    
    // MARK: - Actions
    
    var isDualWatchOn: Bool {
        return effectiveMonitorMode != .off
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
        setScanning(!isScanning)
    }

    public func setScanning(_ shouldScan: Bool) {
        print("RadioManager: setScanning(\(shouldScan))")
        guard let controller = radioController,
              controller.state?.settings != nil else {
            print("RadioManager: No controller or state!")
            return
        }
        guard shouldScan != isScanning else { return }

        let previousSettings = controller.state?.settings ?? .empty()
        if shouldScan {
            scanReturnDoubleChannel = previousSettings.doubleChannel
        }

        isBusy = true
        scanStateOverride = shouldScan
        Task {
            do {
                var updatedSettings = try await controller.refreshSettings()
                updatedSettings.scan = shouldScan

                var shouldSetRadioMode = false
                if shouldScan {
                    updatedSettings.doubleChannel = ChannelType.off.toProtocolValue()
                    shouldSetRadioMode = true
                } else if let returnMode = scanReturnDoubleChannel {
                    updatedSettings.doubleChannel = returnMode
                    shouldSetRadioMode = true
                }

                print("RadioManager: Scan write settings channelA=\(updatedSettings.channelA) channelB=\(updatedSettings.channelB) scan=\(updatedSettings.scan) doubleChannel=\(updatedSettings.doubleChannel)")

                try await controller.setSettings(updatedSettings)
                if shouldSetRadioMode {
                    try await controller.setRadioMode(0)
                }

                if !shouldScan {
                    scanReturnDoubleChannel = nil
                }

                if controller.state?.status.isScan == shouldScan || controller.state?.settings.scan == shouldScan {
                    scanStateOverride = nil
                }

                print("RadioManager: Scan state updated successfully")
                isBusy = false
            } catch {
                if shouldScan {
                    scanReturnDoubleChannel = nil
                }
                scanStateOverride = nil
                print("RadioManager: Failed to set scan state: \(error)")
                errorMessage = "Failed to set scan state: \(error.localizedDescription)"
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
        if index < 250 {
            lastMemoryChannelAIndex = index
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
        if index < 250 {
            lastMemoryChannelBIndex = index
        }
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
                setChannelA(restoredMemoryChannelIndex(for: .a))
            } else {
                setChannelA(vfoIndex)
            }
        } else if channel == .b {
             if isVFOB {
                setChannelB(restoredMemoryChannelIndex(for: .b))
            } else {
                setChannelB(vfoIndex - 1) // confirmed on 251
            }
        }
    }

    private func restoredMemoryChannelIndex(for channel: ChannelType) -> Int {
        let rememberedIndex: Int?
        let currentIndex: Int

        switch channel {
        case .a:
            rememberedIndex = lastMemoryChannelAIndex
            currentIndex = vfoAIndex
        case .b:
            rememberedIndex = lastMemoryChannelBIndex
            currentIndex = vfoBIndex
        case .off:
            return 0
        }

        if let rememberedIndex, rememberedIndex < 250 {
            return rememberedIndex
        }

        if currentIndex < 250 {
            return currentIndex
        }

        return 0
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
    
    /// Selects a VFO and tunes it directly.
    public func tuneVFO(_ frequency: Double, for channel: ChannelType) async throws {
        guard let controller = radioController, channel != .off else {
            throw BLEError.notConnected
        }

        let vfoID = channel == .a ? 252 : 251
        isBusy = true
        defer { isBusy = false }

        var settings = try await controller.refreshSettings()
        switch channel {
        case .a:
            if settings.channelA < 250 {
                lastMemoryChannelAIndex = settings.channelA
            }
            settings.channelA = vfoID
        case .b:
            if settings.channelB < 250 {
                lastMemoryChannelBIndex = settings.channelB
            }
            settings.channelB = vfoID
        case .off:
            throw BLEError.notConnected
        }

        try await controller.setSettings(settings)
        try await controller.setChannel(vfoID, txFreq: frequency, rxFreq: frequency)
    }

    /// Set frequency for VFO without requiring callers to manage an asynchronous task.
    public func setFrequency(_ frequency: Double, for channel: ChannelType) {
        Task {
            do {
                try await tuneVFO(frequency, for: channel)
            } catch {
                print("Failed to set VFO frequency: \(error)")
                errorMessage = "Failed to set VFO frequency: \(error.localizedDescription)"
            }
        }
    }

    public func setFrequencyScan(
        frequencyMHz: Double,
        mode: FrequencyMode,
        stepKHz: Double
    ) async throws {
        guard let controller = radioController else { throw BLEError.notConnected }
        isBusy = true
        defer { isBusy = false }
        try await controller.setFrequencyScan(
            frequencyMHz: frequencyMHz,
            mode: mode,
            step: FrequencyScanStep(kHz: stepKHz)
        )
    }

    public func getFrequencyScanStatus() async throws -> FrequencyModeStatus {
        guard let controller = radioController else { throw BLEError.notConnected }
        return try await controller.getFrequencyScanStatus()
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
                try await controller.setChannel(ch)
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

    public func getAPRSPath() async throws -> String {
        guard let controller = radioController else {
            throw RadioError.stateNotInitialized
        }
        return try await controller.getAPRSPath()
    }

    public func setAPRSPath(_ path: String) async throws {
        guard let controller = radioController else {
            throw RadioError.stateNotInitialized
        }
        try await controller.setAPRSPath(path)
    }
}
