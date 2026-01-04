//
//  ChannelViewModel.swift
//  FieldHT
//
//  Created by Benjamin Faershtein on 12/14/25.
//

import Foundation
import Combine

/// View model for managing radio channels
@MainActor
public class ChannelViewModel: ObservableObject {
    @Published public var channels: [Channel] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String?
    @Published public var isSaving: Bool = false
    
    private var radioController: RadioController?
    private var eventHandler: (() -> Void)?
    private var hydrationTask: Task<Void, Never>?
    
    public init() {}
    
    /// Set the radio controller and load channels
    public func setRadioController(_ controller: RadioController?) {
        print("ChannelViewModel: setRadioController called with \(controller == nil ? "nil" : "controller")")
        radioController = controller
        
        if let controller = controller {
            loadChannels()
            observeChannelChanges(controller)
        } else {
            channels = []
            regions = []
        }
    }
    
    @Published public var regions: [String] = [] // Region names
    @Published public var activeRegionIndex: Int = 0
    
    public var activeRegionName: String {
        if activeRegionIndex < regions.count {
            return regions[activeRegionIndex]
        }
        return "Unknown"
    }
    
    public var supportsDMR: Bool {
        return radioController?.deviceInfo.supportsDMR ?? false
    }

    public func loadChannels() {
        if let controller = radioController {
            isLoading = true
            errorMessage = nil
            print("ChannelViewModel: Loading channels...")
            
            // Since channels are already hydrated in RadioController, we can just grab them
            channels = controller.channelsForCurrentRegion
            
            // Load Regions
            regions = controller.regionNames
            
            // Get active region from status
            activeRegionIndex = controller.status.currRegion
            
            isLoading = false
            print("ChannelViewModel: Loaded \(channels.count) channels and \(regions.count) regions. Active Region: \(activeRegionIndex)")
        }
    }
    
    /// Trigger a targeted channel refresh from the radio
    public func refreshChannels() {
        guard let controller = radioController else { return }
        
        hydrationTask?.cancel()
        isLoading = true
        
        hydrationTask = Task {
            do {
                try await controller.hydrateChannels()
                
                if Task.isCancelled { return }
                
                await MainActor.run {
                    self.loadChannels()
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Failed to refresh channels: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func observeChannelChanges(_ controller: RadioController) {
        // Observe status (region) changes as well?
        // RadioController typically updates state on events.
        
        eventHandler = controller.addEventHandler { [weak self] event in
            Task { @MainActor in
                guard let self = self else { return }
                
                // Always refresh data if likely changed
                self.channels = controller.channelsForCurrentRegion
                self.regions = controller.regionNames
                self.activeRegionIndex = controller.status.currRegion
            }
        }
    }
    
    /// Update a channel
    public func updateChannel(_ channel: Channel) {
        guard let radioController = radioController else { return }
        
        isSaving = true
        errorMessage = nil
        
        Task {
            do {
                // 1. Save channel details
                try await radioController.setChannel(channel)
                
                // 2. Assign channel to current active region (User Request)
                print("ChannelViewModel: Auto-assigning Ch \(channel.channelID) to Region \(self.activeRegionIndex)")
                try await radioController.assignChannelToRegion(
                    regionID: self.activeRegionIndex,
                    channelID: channel.channelID
                )
                
                await MainActor.run {
                    self.isSaving = false
                    // Update list from controller (which updated local state)
                    self.channels = radioController.channelsForCurrentRegion
                    self.activeRegionIndex = radioController.status.currRegion
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to save channel: \(error.localizedDescription)"
                }
            }
        }
    }
    
    /// Delete a channel by replacing it with a default empty channel
    public func deleteChannel(_ channel: Channel) {
        guard let radioController = radioController else { return }
        
        isSaving = true
        errorMessage = nil
        
        Task {
            do {
                // Create a default empty channel with the same ID
                var defaultChannel = Channel.empty(channelID: channel.channelID)
                defaultChannel.channelID = channel.channelID
                
                print("ChannelViewModel: Replacing channel \(channel.channelID) with default empty channel")
                try await radioController.setChannel(defaultChannel)
                
                // Wait for the radio to process the change
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                
                // Refresh channels from the radio
                try await radioController.hydrateChannels()
                
                await MainActor.run {
                    self.isSaving = false
                    self.loadChannels()
                }
            } catch {
                await MainActor.run {
                    self.isSaving = false
                    self.errorMessage = "Failed to delete channel: \(error.localizedDescription)"
                }
            }
        }
    }
    
    /// Set current active region
    public func setActiveRegion(_ index: Int) {
        guard let radioController = radioController else { return }
        
        hydrationTask?.cancel()
        isSaving = true
        
        hydrationTask = Task {
            do {
                print("ChannelViewModel: Switching to region \(index)")
                try await radioController.setRegion(index)
                
                await MainActor.run {
                    self.isSaving = false
                    self.loadChannels()
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to switch region: \(error.localizedDescription)"
                }
            }
        }
    }
    
    /// Rename region
    public func renameRegion(_ index: Int, name: String) {
        guard let radioController = radioController else { return }
        isSaving = true
        Task {
            do {
                try await radioController.setRegionName(index, name: name)
                await MainActor.run {
                    self.isSaving = false
                    self.regions = radioController.regionNames
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to rename region: \(error.localizedDescription)"
                }
            }
        }
    }
}
