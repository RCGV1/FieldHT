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
    
    @Published public var batteryVoltage: Double = 0.0
    @Published public var batteryLevel: Int = 0
    
    @Published public var isBusy: Bool = false
    @Published public var errorMessage: String?
    
    private var connectionTask: Task<Void, Never>?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    public init() {}
    
    /// Connect to a radio device
    public func connect(to deviceUUID: UUID) {
        guard !isConnecting && !isConnected else { return }
        
        isConnecting = true
        connectionError = nil
        
        connectionTask = Task {
            do {
                let radio = RadioController.newBLE(deviceUUID: deviceUUID, radioManager: self)
                // Subscribe to changes from the controller before connecting
                subscribeToRadio(radio)
                
                try await radio.connect()
                
                self.radioController = radio
                self.isConnected = true
                self.isConnecting = false
                
                // Start polling for battery
                startPolling()
            } catch {
                self.connectionError = error.localizedDescription
                self.isConnecting = false
                self.radioController = nil
                self.cancellables.removeAll()
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
        connectionTask?.cancel()
        connectionTask = nil
        stopPolling()
        cancellables.removeAll()
        
        Task {
            if let radio = radioController {
                await radio.disconnect()
            }
            
            await MainActor.run {
                self.radioController = nil
                self.isConnected = false
                self.connectionError = nil
            }
        }
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
}
