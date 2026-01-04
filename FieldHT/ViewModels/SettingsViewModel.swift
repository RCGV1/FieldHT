//
//  SettingsViewModel.swift
//  FieldHT
//
//  Created by Benjamin Faershtein on 12/13/25.
//

import Foundation
import Combine

/// View model for managing radio settings
@MainActor
public class SettingsViewModel: ObservableObject {
    @Published public var settings: Settings?
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String?
    @Published public var isSaving: Bool = false
    
    private var radioController: RadioController?
    private var settingsTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var eventHandler: (() -> Void)?
    
    public init() {}
    
    /// Set the radio controller and load settings
    public func setRadioController(_ controller: RadioController?) {
        print("SettingsViewModel: setRadioController called with \(controller == nil ? "nil" : "controller")")
        // Cancel previous task
        settingsTask?.cancel()
        eventHandler?()
        
        radioController = controller
        
        if let controller = controller {
            loadSettings()
            observeSettingsChanges(controller)
        } else {
            settings = nil
            print("SettingsViewModel: Controller is nil, settings cleared")
        }
    }
    
    public func retryLoad() {
        print("SettingsViewModel: Retrying load...")
        loadSettings()
    }
    
    /// Load settings from the radio
    private func loadSettings() {
        guard let radioController = radioController else {
            print("SettingsViewModel: loadSettings failed - no radio controller")
            return
        }
        
        isLoading = true
        errorMessage = nil
        print("SettingsViewModel: Starting load settings...")
        
        settingsTask = Task {
            // Wait a bit to ensure radio is fully hydrated after connection
            // The radio needs time to complete the hydrate() process
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Check if radio is connected and has state
            guard radioController.isConnected else {
                await MainActor.run {
                    self.errorMessage = "Radio not fully connected"
                    self.isLoading = false
                    print("SettingsViewModel: Radio not connected (isConnected=false), cannot load settings")
                }
                return
            }
            
            // Access settings - isConnected already ensures state != nil
            // so this should be safe, but we'll add a check anyway
            await MainActor.run {
                // Double-check connection status on main actor
                guard radioController.isConnected else {
                    self.errorMessage = "Radio disconnected during load"
                    self.isLoading = false
                    print("SettingsViewModel: Radio disconnected during load check")
                    return
                }
                
                // Access settings - this is safe if isConnected is true
                let currentSettings = radioController.settings
                self.settings = currentSettings
                self.isLoading = false
                self.errorMessage = nil
                print("SettingsViewModel: Successfully loaded settings - Channel A: \(currentSettings.channelA), Channel B: \(currentSettings.channelB)")
            }
        }
    }
    
    /// Observe settings changes from the radio
    private func observeSettingsChanges(_ controller: RadioController) {
        eventHandler = controller.addEventHandler { [weak self] event in
            Task { @MainActor in
                guard let self = self else { return }
                if case .settingsChanged(let newSettings) = event {
                    self.settings = newSettings
                }
            }
        }
    }
    var isDualWatchOn: Bool {
        return settings?.doubleChannel != ChannelType.off.toProtocolValue()
    }

    func setDualWatch(_ isOn: Bool) {
        let newValue: ChannelType = isOn ? .a : .off
        updateDoubleChannel(newValue.toProtocolValue())
    }
    
    /// Update settings with a new Settings object
    public func updateSettings(_ newSettings: Settings) {
        guard let radioController = radioController else {
            return // Not connected
        }
        
        // Optimistic update
        self.settings = newSettings
        
        // Cancel previous pending save
        saveTask?.cancel()
        saveTask = Task {
            // Debounce: Wait 0.5s before sending
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            if Task.isCancelled { return }
            
            await MainActor.run {
                self.isSaving = true
                self.errorMessage = nil
                print("SettingsViewModel: Attempting to save settings: \(newSettings)")
            }
            
            do {
                try await radioController.setSettings(newSettings)
                await MainActor.run {
                    self.isSaving = false
                    print("SettingsViewModel: Settings saved successfully")
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.isSaving = false
                    self.errorMessage = error.localizedDescription
                    // Revert on failure? Or just show error?
                    // Reverting might be annoying if user is still typing/sliding.
                    // For now, let's just log and show error.
                    print("SettingsViewModel: Failed to save settings. Error: \(error)")
                    if let protocolError = error as? ProtocolError, case .commandFailed(let status, let msg) = protocolError {
                        print("SettingsViewModel: Command Failed Status: \(status), Message: \(msg)")
                    }
                }
            }
        }
    }
    
    /// Update channelA
    public func updateChannelA(_ value: Int) {
        guard var current = settings else { return }
        current.channelA = value
        updateSettings(current)
    }
    
    /// Update channelB
    public func updateChannelB(_ value: Int) {
        guard var current = settings else { return }
        current.channelB = value
        updateSettings(current)
    }
    
    /// Update scan
    public func updateScan(_ value: Bool) {
        guard var current = settings else { return }
        current.scan = value
        updateSettings(current)
    }
    
    /// Update squelchLevel
    public func updateSquelchLevel(_ value: Int) {
        guard var current = settings else { return }
        current.squelchLevel = value
        updateSettings(current)
    }
    
    /// Update micGain
    public func updateMicGain(_ value: Int) {
        guard var current = settings else { return }
        current.micGain = value
        updateSettings(current)
    }
    
    /// Update btMicGain
    public func updateBtMicGain(_ value: Int) {
        guard var current = settings else { return }
        current.btMicGain = value
        updateSettings(current)
    }
    
    /// Update localSpeaker
    public func updateLocalSpeaker(_ value: Int) {
        guard var current = settings else { return }
        current.localSpeaker = value
        updateSettings(current)
    }
    
    /// Update hmSpeaker
    public func updateHmSpeaker(_ value: Int) {
        guard var current = settings else { return }
        current.hmSpeaker = value
        updateSettings(current)
    }
    
    /// Update txHoldTime
    public func updateTxHoldTime(_ value: Int) {
        guard var current = settings else { return }
        current.txHoldTime = value
        updateSettings(current)
    }
    
    /// Update txTimeLimit
    public func updateTxTimeLimit(_ value: Int) {
        guard var current = settings else { return }
        current.txTimeLimit = value
        updateSettings(current)
    }
    
    /// Update autoPowerOff
    public func updateAutoPowerOff(_ value: Int) {
        guard var current = settings else { return }
        current.autoPowerOff = value
        updateSettings(current)
    }
    
    /// Update screenTimeout
    public func updateScreenTimeout(_ value: Int) {
        guard var current = settings else { return }
        current.screenTimeout = value
        updateSettings(current)
    }
    
    /// Update tailElim
    public func updateTailElim(_ value: Bool) {
        guard var current = settings else { return }
        current.tailElim = value
        updateSettings(current)
    }
    
    /// Update autoRelayEn
    public func updateAutoRelayEn(_ value: Bool) {
        guard var current = settings else { return }
        current.autoRelayEn = value
        updateSettings(current)
    }
    
    /// Update autoPowerOn
    public func updateAutoPowerOn(_ value: Bool) {
        guard var current = settings else { return }
        current.autoPowerOn = value
        updateSettings(current)
    }
    
    /// Update keepAghfpLink
    public func updateKeepAghfpLink(_ value: Bool) {
        guard var current = settings else { return }
        current.keepAghfpLink = value
        updateSettings(current)
    }
    
    /// Update adaptiveResponse
    public func updateAdaptiveResponse(_ value: Bool) {
        guard var current = settings else { return }
        current.adaptiveResponse = value
        updateSettings(current)
    }
    
    /// Update disTone
    public func updateDisTone(_ value: Bool) {
        guard var current = settings else { return }
        current.disTone = value
        updateSettings(current)
    }
    
    /// Update powerSavingMode
    public func updatePowerSavingMode(_ value: Bool) {
        guard var current = settings else { return }
        current.powerSavingMode = value
        updateSettings(current)
    }
    
    /// Update useFreqRange2
    public func updateUseFreqRange2(_ value: Bool) {
        guard var current = settings else { return }
        current.useFreqRange2 = value
        updateSettings(current)
    }
    
    /// Update pttLock
    public func updatePttLock(_ value: Bool) {
        guard var current = settings else { return }
        current.pttLock = value
        updateSettings(current)
    }
    
    /// Update leadingSyncBitEn
    public func updateLeadingSyncBitEn(_ value: Bool) {
        guard var current = settings else { return }
        current.leadingSyncBitEn = value
        updateSettings(current)
    }
    
    /// Update pairingAtPowerOn
    public func updatePairingAtPowerOn(_ value: Bool) {
        guard var current = settings else { return }
        current.pairingAtPowerOn = value
        updateSettings(current)
    }
    
    /// Update imperialUnit
    public func updateImperialUnit(_ value: Bool) {
        guard var current = settings else { return }
        current.imperialUnit = value
        updateSettings(current)
    }
    
    /// Update disDigitalMute
    public func updateDisDigitalMute(_ value: Bool) {
        guard var current = settings else { return }
        current.disDigitalMute = value
        updateSettings(current)
    }
    
    /// Update signalingEccEn
    public func updateSignalingEccEn(_ value: Bool) {
        guard var current = settings else { return }
        current.signalingEccEn = value
        updateSettings(current)
    }
    
    /// Update chDataLock
    public func updateChDataLock(_ value: Bool) {
        guard var current = settings else { return }
        current.chDataLock = value
        updateSettings(current)
    }
    
    /// Update Double Channel
    public func updateDoubleChannel(_ value: Int) {
        guard var current = settings else { return }
        current.doubleChannel = value
        updateSettings(current)
    }
}

enum SettingsError: LocalizedError {
    case notConnected
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to radio"
        }
    }
}
