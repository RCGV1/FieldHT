//
//  ChannelViewModel.swift
//  FieldHT
//
//  Created by Benjamin Faershtein on 12/14/25.
//

import Foundation
import Combine
import SwiftUI

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
    private var stateCancellable: AnyCancellable?
    
    public init() {}

    deinit {
        eventHandler?()
        stateCancellable?.cancel()
        hydrationTask?.cancel()
    }

    private func clampedRegionIndex(_ regionIndex: Int, regionCount: Int) -> Int {
        guard regionCount > 0 else { return 0 }
        return min(max(regionIndex, 0), regionCount - 1)
    }
    
    /// Set the radio controller and load channels
    public func setRadioController(_ controller: RadioController?) {
        print("ChannelViewModel: setRadioController called with \(controller == nil ? "nil" : "controller")")
        eventHandler?()
        eventHandler = nil
        stateCancellable?.cancel()
        stateCancellable = nil
        hydrationTask?.cancel()
        hydrationTask = nil

        radioController = controller
        
        if let controller = controller {
            loadChannels()
            observeStateChanges(controller)
            observeChannelChanges(controller)
        } else {
            channels = []
            regions = []
            activeRegionIndex = 0
            isLoading = false
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
            activeRegionIndex = clampedRegionIndex(controller.status.currRegion, regionCount: regions.count)
            
            isLoading = false
            print("ChannelViewModel: Loaded \(channels.count) channels and \(regions.count) regions. Active Region: \(activeRegionIndex)")
        }
    }

    public func channel(withID channelID: Int) -> Channel? {
        channels.first { $0.channelID == channelID }
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
                self.activeRegionIndex = self.clampedRegionIndex(controller.status.currRegion, regionCount: self.regions.count)
            }
        }
    }

    private func observeStateChanges(_ controller: RadioController) {
        stateCancellable = controller.$state.sink { [weak self, weak controller] _ in
            Task { @MainActor [weak self, weak controller] in
                await Task.yield()
                guard let self, let controller, self.radioController === controller else { return }
                self.loadChannels()
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
                    self.activeRegionIndex = self.clampedRegionIndex(radioController.status.currRegion, regionCount: self.regions.count)
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
    
    /// Add channels locally (for offline mode when radio not connected)
    public func addChannelsLocally(_ csvChannels: [Channel]) {
        let existingChannels = channels
        
        // Find empty slots
        var emptySlots: [Int] = []
        for i in 0..<30 {
            if !existingChannels.contains(where: { $0.channelID == i }) {
                emptySlots.append(i)
            }
        }
        
        var importedChannels: [Channel] = []
        var slotIndex = 0
        
        for (idx, csvChannel) in csvChannels.enumerated() {
            if idx < existingChannels.count {
                // Replace existing
                var updated = csvChannel
                updated.channelID = existingChannels[idx].channelID
                importedChannels.append(updated)
            } else if slotIndex < emptySlots.count {
                // Put in empty slot
                var updated = csvChannel
                updated.channelID = emptySlots[slotIndex]
                importedChannels.append(updated)
                slotIndex += 1
            } else {
                break
            }
        }
        
        // Merge with existing
        var allChannels = existingChannels
        for imported in importedChannels {
            if let existingIdx = allChannels.firstIndex(where: { $0.channelID == imported.channelID }) {
                allChannels[existingIdx] = imported
            } else {
                allChannels.append(imported)
            }
        }
        
        // Sort by channel ID
        allChannels.sort { $0.channelID < $1.channelID }
        
        channels = allChannels
    }
    
    // MARK: - Reorder & Insert

    /// Regular memory channels (excluding VFO slots at 251/252), sorted by slot.
    public var regularChannels: [Channel] {
        channels.filter { $0.channelID < 250 }.sorted { $0.channelID < $1.channelID }
    }

    /// VFO channels (slot IDs ≥ 250), sorted by slot.
    public var vfoChannels: [Channel] {
        channels.filter { $0.channelID >= 250 }.sorted { $0.channelID < $1.channelID }
    }

    /// Reorder channels by swapping hardware slot contents.
    /// Called from List.onMove; writes only the slots whose content changed.
    public func moveChannels(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let radioController else { return }
        let regular = regularChannels
        let originalSlots = regular.map { $0.channelID }

        var reordered = regular
        reordered.move(fromOffsets: source, toOffset: destination)

        var toWrite: [Channel] = []
        for (i, content) in reordered.enumerated() {
            let targetSlot = originalSlots[i]
            guard content.channelID != targetSlot else { continue }
            var updated = content
            updated.channelID = targetSlot
            toWrite.append(updated)
        }
        guard !toWrite.isEmpty else { return }

        isSaving = true
        Task {
            do {
                for ch in toWrite { try await radioController.setChannel(ch) }
                try await radioController.hydrateChannels()
                await MainActor.run { self.loadChannels(); self.isSaving = false }
            } catch {
                await MainActor.run {
                    self.isSaving = false
                    self.errorMessage = "Reorder failed: \(error.localizedDescription)"
                    self.loadChannels()
                }
            }
        }
    }

    /// Returns true if inserting before `channelID` would overwrite the last occupied slot (slot 29).
    public func insertWouldOverwrite(before channelID: Int) -> Bool {
        let regular = regularChannels
        guard regular.firstIndex(where: { $0.channelID == channelID }) != nil else { return false }
        guard let last = regular.last, last.channelID == 29 else { return false }
        return !(last.rxFreq == 0 && last.txFreq == 0 && last.name.isEmpty)
    }

    /// Shift channels from `channelID` onward down by one slot and write an empty channel at that slot.
    public func insertEmptyChannel(before channelID: Int) {
        guard let radioController else { return }
        let regular = regularChannels
        guard let insertIdx = regular.firstIndex(where: { $0.channelID == channelID }) else { return }

        let insertionSlotID = regular[insertIdx].channelID
        let channelsToShift = Array(regular[insertIdx...])

        isSaving = true
        Task {
            do {
                // Write in reverse so we never overwrite a source before it has been copied
                for ch in channelsToShift.reversed() {
                    let newSlotID = ch.channelID + 1
                    guard newSlotID < 30 else { continue }   // slot 30+ doesn't exist — last slot drops
                    var shifted = ch
                    shifted.channelID = newSlotID
                    try await radioController.setChannel(shifted)
                }
                try await radioController.setChannel(Channel.empty(channelID: insertionSlotID))
                try await radioController.hydrateChannels()
                await MainActor.run { self.loadChannels(); self.isSaving = false }
            } catch {
                await MainActor.run {
                    self.isSaving = false
                    self.errorMessage = "Insert failed: \(error.localizedDescription)"
                    self.loadChannels()
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
        #if DEBUG
        let hexString = name.data(using: .utf8)?.map { String(format: "%02x", $0) }.joined() ?? "nil"
        print("DEBUG: Renaming region \(index) to '\(name)' (hex: \(hexString))")
        #endif

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
