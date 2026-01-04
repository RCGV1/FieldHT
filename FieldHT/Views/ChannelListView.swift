//
//  ChannelListView.swift
//  FieldHT
//
//  Created by Benjamin Faershtein on 12/14/25.
//

import SwiftUI

struct ChannelListView: View {
    @StateObject private var viewModel = ChannelViewModel()
    @EnvironmentObject var radioManager: RadioManager

    var radioController: RadioController?

    @State private var showRegions = false
    @State private var isHydrating = false
    @State private var retryCount = 0
    @State private var isManualSwitch = false

    private let maxRetries = 3

    var body: some View {
        ZStack {
            List {
                if !viewModel.regions.isEmpty {
                    Section(header: Text("Current Memory Group")) {
                        Picker("Active Group", selection: Binding(
                            get: { viewModel.activeRegionIndex },
                            set: { newIndex in
                                isManualSwitch = true
                                Task {
                                    await hydrateAndSwitchRegion(to: newIndex)
                                }
                            }
                        )) {
                            ForEach(0..<viewModel.regions.count, id: \.self) { index in
                                Text("\(index+1).  \(viewModel.regions[index])").tag(index)
                            }
                        }
                        .disabled(isHydrating)

                        Button(action: { showRegions = true }) {
                            Label("Manage Group Names", systemImage: "pencil")
                        }
                        .disabled(isHydrating)
                    }
                }

                if viewModel.isLoading {
                    ProgressView("Loading channels...")
                } else if viewModel.channels.isEmpty {
                    Text("No channels found")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.channels, id: \.channelID) { channel in
                        NavigationLink(destination: ChannelDetailView(channel: channel, viewModel: viewModel)) {
                            HStack {
                                Text(String(format: "%03d", channel.channelID + 1))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .padding(4)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(4)

                                VStack(alignment: .leading) {
                                    Text(channel.name.isEmpty ? "Channel \(channel.channelID + 1)" : channel.name)
                                        .font(.headline)
                                    Text(String(format: "%.5f MHz", channel.rxFreq))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if channel.txDisable {
                                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                        .font(.caption)
                                }
                            }
                        }
                        .disabled(isHydrating)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deleteChannel(channel)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .blur(radius: isHydrating ? 3 : 0)

            // Hydration loading overlay
            if isHydrating {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))

                        Text(retryCount > 0
                            ? "Syncing with radio... (Attempt \(retryCount + 1)/\(maxRetries))"
                            : "Syncing with radio...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemBackground))
                            .shadow(radius: 20)
                    )
                }
            }
        }
        .navigationTitle("Channels")
        .onAppear {
                let controller = radioController ?? radioManager.radioController
                viewModel.setRadioController(controller)
                viewModel.loadChannels()

        }
        .onChange(of: radioManager.activeRegionIndex) {
            // Only hydrate if this wasn't triggered by our manual switch
            guard !isManualSwitch else {
                isManualSwitch = false
                return
            }
            
            Task {
                await hydrateAndReload()
            }
        }
        .onChange(of: radioManager.isConnected) { _, isConnected in
            if isConnected {
                // Wait for hydration
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await MainActor.run {
                        viewModel.setRadioController(radioManager.radioController)
                    }
                }
            } else {
                viewModel.setRadioController(nil)
            }
        }
        .sheet(isPresented: $showRegions) {
            RegionManagementView(viewModel: viewModel)
        }
    }

    // Helper function to hydrate and reload with loading indicator and retry logic
    private func hydrateAndReload() async {
        await MainActor.run {
            isHydrating = true
            retryCount = 0
        }

        let backoffs = [5, 10, 15]
        var lastError: Error?

        for attempt in 0..<maxRetries {
            await MainActor.run {
                retryCount = attempt
            }

            do {
                try await radioManager.radioController?.hydrateChannels()
                await MainActor.run {
                    viewModel.loadChannels()
                    isHydrating = false
                    retryCount = 0
                }
                return // Success - exit the function
            } catch is CancellationError {
                print("Hydration attempt \(attempt + 1) was cancelled")
                // If cancelled, try to load from cache and exit
                await MainActor.run {
                    viewModel.loadChannels()
                    isHydrating = false
                    retryCount = 0
                }
                return
            } catch {
                lastError = error
                print("Hydration attempt \(attempt + 1) failed: \(error)")

                // If not the last attempt, wait before retrying
                if attempt < maxRetries - 1 {
                    let delaySeconds = backoffs[attempt]
                    let delay = UInt64(delaySeconds) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }

        // All retries failed - load from cache anyway
        await MainActor.run {
            viewModel.loadChannels()
            isHydrating = false
            retryCount = 0
            viewModel.errorMessage = "Failed to update channels after \(maxRetries) attempts: \(lastError?.localizedDescription ?? "Unknown error")"
        }
    }
    
    // Helper function to switch region and hydrate
    private func hydrateAndSwitchRegion(to index: Int) async {
        await MainActor.run {
            isHydrating = true
            retryCount = 0
        }

        do {
            print("ChannelListView: Switching to region \(index)")
            try await radioManager.radioController?.setRegion(index)
            
            // Wait for radio to process region change
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            
            print("ChannelListView: Hydrating new region...")
            try await radioManager.radioController?.hydrateChannels()
            
            await MainActor.run {
                viewModel.loadChannels()
                isHydrating = false
                retryCount = 0
                isManualSwitch = false // Reset the flag
            }
        } catch is CancellationError {
            print("ChannelListView: Region switch was cancelled")
            await MainActor.run {
                // Still try to load channels from cache even if cancelled
                viewModel.loadChannels()
                isHydrating = false
                retryCount = 0
                isManualSwitch = false
            }
        } catch {
            print("ChannelListView: Region switch failed: \(error)")
            await MainActor.run {
                // Try to load from cache on error
                viewModel.loadChannels()
                isHydrating = false
                retryCount = 0
                isManualSwitch = false
                viewModel.errorMessage = "Failed to switch region: \(error.localizedDescription)"
            }
        }
    }
}
