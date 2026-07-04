//
//  ChannelListView.swift
//  FieldHT
//
//  Created by Benjamin Faershtein on 12/14/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct ChannelListView: View {
    @StateObject private var viewModel = ChannelViewModel()
    @EnvironmentObject var radioManager: RadioManager

    var radioController: RadioController?

    @State private var showRegions = false
    @State private var isHydrating = false
    @State private var retryCount = 0
    @State private var isManualSwitch = false
    @State private var showImportPicker = false
    @State private var isImporting = false
    @State private var importError: String?
    @State private var insertTarget: Channel? = nil   // pending insert-before confirmation
    @State private var showDocumentImportPicker = false
    @State private var importedDocumentChannels: [Channel] = []
    @State private var showDocumentImportPreview = false
    @State private var importStatusMessage = "Analyzing\u{2026}"
    @State private var isDocumentImporting = false

    private let maxRetries = 3
    
    private var overlayMessage: String {
        if isDocumentImporting {
            return importStatusMessage
        }
        if isImporting {
            return "Importing channels..."
        }
        if viewModel.isSaving {
            return "Saving to radio..."
        }
        if retryCount > 0 {
            return "Syncing with radio... (Attempt \(retryCount + 1)/\(maxRetries))"
        }
        return "Syncing with radio..."
    }

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
                            ForEach(Array(viewModel.regions.enumerated()), id: \.offset) { index, region in
                                Text("\(index+1).  \(region)").tag(index)
                            }
                        }
                        .disabled(isHydrating || isImporting || isDocumentImporting)

                        Button(action: { showRegions = true }) {
                            Label("Manage Group Names", systemImage: "pencil")
                        }
                        .disabled(isHydrating || isImporting || isDocumentImporting)
                        
                        Button(action: { showImportPicker = true }) {
                            Label("Import from CSV", systemImage: "square.and.arrow.down")
                        }
                        .disabled(isHydrating || isImporting || isDocumentImporting)

                        Button(action: { showDocumentImportPicker = true }) {
                            Label("Import from Document", systemImage: "doc.text.magnifyingglass")
                        }
                        .disabled(isHydrating || isImporting || isDocumentImporting)

                        if let error = importError {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .padding(.top, 2)

                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if viewModel.isLoading {
                    ProgressView("Loading channels...")
                } else if viewModel.channels.isEmpty {
                    ContentUnavailableView(
                        "No Channels Yet",
                        systemImage: "waveform.badge.magnifyingglass",
                        description: Text("Import channel data from CSV, PDF, or text files, or connect to hydrate channels from the radio.")
                    )
                } else {
                    ForEach(viewModel.regularChannels, id: \.channelID) { channel in
                        NavigationLink(destination: ChannelDetailView(channel: channel, viewModel: viewModel)) {
                            ChannelRowView(channel: channel)
                        }
                        .disabled(isHydrating || isImporting || isDocumentImporting || viewModel.isSaving)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deleteChannel(channel)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                if viewModel.insertWouldOverwrite(before: channel.channelID) {
                                    insertTarget = channel
                                } else {
                                    viewModel.insertEmptyChannel(before: channel.channelID)
                                }
                            } label: {
                                Label("Insert Before", systemImage: "plus.rectangle.on.rectangle")
                            }
                            .tint(.blue)
                        }
                    }
                    .onMove { source, destination in
                        viewModel.moveChannels(fromOffsets: source, toOffset: destination)
                    }

                    if !viewModel.vfoChannels.isEmpty {
                        Section(header: Text("VFO")) {
                            ForEach(viewModel.vfoChannels, id: \.channelID) { channel in
                                NavigationLink(destination: ChannelDetailView(channel: channel, viewModel: viewModel)) {
                                    ChannelRowView(channel: channel, isVFO: true)
                                }
                                .disabled(isHydrating || isImporting || isDocumentImporting || viewModel.isSaving)
                            }
                        }
                    }
                }
            }
            .blur(radius: isHydrating || isImporting || isDocumentImporting || viewModel.isSaving ? 3 : 0)

            // Hydration/Import/Saving loading overlay
            if isHydrating || isImporting || isDocumentImporting || viewModel.isSaving {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))

                        Text(overlayMessage)
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
        .alert("Last Channel Will Be Overwritten", isPresented: Binding(
            get: { insertTarget != nil },
            set: { if !$0 { insertTarget = nil } }
        )) {
            Button("Insert Anyway", role: .destructive) {
                if let target = insertTarget {
                    viewModel.insertEmptyChannel(before: target.channelID)
                }
                insertTarget = nil
            }
            Button("Cancel", role: .cancel) { insertTarget = nil }
        } message: {
            Text("Inserting here will shift all channels down by one slot. The channel currently at slot 30 will be lost. Continue?")
        }
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
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.commaSeparatedText, UTType(filenameExtension: "csv") ?? .commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            Task {
                await handleImport(result: result)
            }
        }
        .fileImporter(
            isPresented: $showDocumentImportPicker,
            allowedContentTypes: [.data, .pdf, .commaSeparatedText, .text, .plainText],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleDocumentImport(result: result) }
        }
        .sheet(isPresented: $showDocumentImportPreview) {
            AIImportPreviewSheet(channels: importedDocumentChannels) { channels in
                Task { await commitChannels(channels) }
            }
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
    
    // MARK: - CSV Import

    private func handleImport(result: Result<[URL], Error>) async {
        await MainActor.run {
            isImporting = true
            importError = nil
        }

        do {
            guard let fileURL = try result.get().first else {
                await MainActor.run {
                    isImporting = false
                    importError = "No file selected"
                }
                return
            }

            guard fileURL.startAccessingSecurityScopedResource() else {
                await MainActor.run {
                    isImporting = false
                    importError = "Unable to access file"
                }
                return
            }
            defer { fileURL.stopAccessingSecurityScopedResource() }

            let csvString = try String(contentsOf: fileURL, encoding: .utf8)
            let channels = try parseCSV(csvString)

            // Limit to 30 channels
            let channelsToImport = Array(channels.prefix(30))

            await commitChannels(channelsToImport, overflowCount: channels.count > 30 ? channels.count : nil)

        } catch {
            print("ChannelListView: Import error: \(error)")
            await MainActor.run {
                isImporting = false
                importError = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Document Import

    private func handleDocumentImport(result: Result<[URL], Error>) async {
        await MainActor.run {
            isDocumentImporting = true
            importStatusMessage = "Reading file\u{2026}"
            importError = nil
        }
        do {
            guard let fileURL = try result.get().first else {
                await MainActor.run { isDocumentImporting = false; importError = "No file selected" }
                return
            }
            guard fileURL.startAccessingSecurityScopedResource() else {
                await MainActor.run { isDocumentImporting = false; importError = "Unable to access file" }
                return
            }
            defer { fileURL.stopAccessingSecurityScopedResource() }
            let channels = try await AIChannelImporter.parse(url: fileURL) { msg in
                Task { @MainActor in importStatusMessage = msg }
            }
            await MainActor.run {
                importedDocumentChannels = channels
                isDocumentImporting = false
                showDocumentImportPreview = true
            }
        } catch {
            await MainActor.run {
                isDocumentImporting = false
                importError = "Document import failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Commit Channels to Radio

    private func commitChannels(_ channelsToImport: [Channel], overflowCount: Int? = nil) async {
        await MainActor.run {
            isImporting = true
            importError = nil
        }

        print("ChannelListView: Importing \(channelsToImport.count) channels to region \(viewModel.activeRegionIndex)")

        if radioManager.isConnected, let controller = radioManager.radioController {
            await MainActor.run {
                viewModel.isSaving = true
            }

            do {
                let existingChannels = controller.channels(forRegion: viewModel.activeRegionIndex)

                var importedCount = 0
                for (idx, csvChannel) in channelsToImport.enumerated() {
                    if idx < existingChannels.count {
                        var updatedChannel = csvChannel
                        updatedChannel.channelID = existingChannels[idx].channelID
                        try await controller.setChannel(updatedChannel)
                        importedCount += 1
                    } else {
                        break
                    }
                }

                if importedCount < channelsToImport.count {
                    let emptySlots = existingChannels.filter { $0.rxFreq == 0 && $0.txFreq == 0 }
                    var slotIndex = 0

                    for idx in importedCount..<channelsToImport.count {
                        if slotIndex < emptySlots.count {
                            var updatedChannel = channelsToImport[idx]
                            updatedChannel.channelID = emptySlots[slotIndex].channelID
                            try await controller.setChannel(updatedChannel)
                            slotIndex += 1
                        } else {
                            break
                        }
                    }
                }

                try await controller.hydrateChannels()

                await MainActor.run {
                    viewModel.isSaving = false
                    viewModel.loadChannels()
                    isImporting = false
                    if let total = overflowCount {
                        importError = "Imported first 30 of \(total) channels"
                    }
                }
            } catch {
                await MainActor.run {
                    viewModel.isSaving = false
                    importError = "Radio write failed, storing locally: \(error.localizedDescription)"
                }
                viewModel.addChannelsLocally(channelsToImport)
                await MainActor.run {
                    isImporting = false
                }
            }
        } else {
            viewModel.addChannelsLocally(channelsToImport)
            await MainActor.run {
                isImporting = false
                if let total = overflowCount {
                    importError = "Saved \(channelsToImport.count) of \(total) channels locally (not connected to radio)"
                }
            }
        }
    }
    
    private func parseCSV(_ csvString: String) throws -> [Channel] {
        var channels: [Channel] = []
        let lines = csvString.components(separatedBy: .newlines)
        
        guard lines.count > 1 else {
            throw CSVImportError.invalidFormat("File is empty or has no data rows")
        }
        
        // Parse header
        let header = lines[0].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        // Find column indices
        guard let titleIdx = header.firstIndex(of: "title"),
              let txFreqIdx = header.firstIndex(of: "tx_freq"),
              let rxFreqIdx = header.firstIndex(of: "rx_freq") else {
            throw CSVImportError.invalidFormat("Missing required columns: title, tx_freq, rx_freq")
        }
        
        let txSubAudioIdx = header.firstIndex(of: "tx_sub_audio")
        let rxSubAudioIdx = header.firstIndex(of: "rx_sub_audio")
        let txPowerIdx = header.firstIndex(of: "tx_power")
        let bandwidthIdx = header.firstIndex(of: "bandwidth")
        let scanIdx = header.firstIndex(of: "scan")
        let talkAroundIdx = header.firstIndex(of: "talk_around")
        let preDeEmphIdx = header.firstIndex(of: "pre_de_emph_bypass")
        let signIdx = header.firstIndex(of: "sign")
        let txDisIdx = header.firstIndex(of: "tx_dis")
        let muteIdx = header.firstIndex(of: "mute")
        let rxModIdx = header.firstIndex(of: "rx_modulation")
        let txModIdx = header.firstIndex(of: "tx_modulation")
        
        // Parse data rows
        for (index, line) in lines.dropFirst().enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty else { continue }
            
            let values = trimmedLine.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            
            guard values.count >= header.count else {
                print("Warning: Skipping row \(index + 2) - not enough columns")
                continue
            }
            
            // Parse required fields
            let name = values[titleIdx]
            guard let txFreqInt = Int(values[txFreqIdx]),
                  let rxFreqInt = Int(values[rxFreqIdx]) else {
                print("Warning: Skipping row \(index + 2) - invalid frequency")
                continue
            }
            
            let txFreq = Double(txFreqInt) / 100000.0
            let rxFreq = Double(rxFreqInt) / 100000.0
            
            // Parse optional fields
            let txSubAudio = txSubAudioIdx.flatMap { parseSubAudio(values[$0]) }
            let rxSubAudio = rxSubAudioIdx.flatMap { parseSubAudio(values[$0]) }
            let txPower = txPowerIdx.map { values[$0] } ?? "HIGH"
            let bandwidth = bandwidthIdx.flatMap { Int(values[$0]) } ?? 1
            let scan = scanIdx.flatMap { Int(values[$0]) } ?? 1
            let talkAround = talkAroundIdx.flatMap { Int(values[$0]) } ?? 0
            let preDeEmph = preDeEmphIdx.flatMap { Int(values[$0]) } ?? 0
            let sign = signIdx.flatMap { Int(values[$0]) } ?? 0
            let txDis = txDisIdx.flatMap { Int(values[$0]) } ?? 0
            let mute = muteIdx.flatMap { Int(values[$0]) } ?? 0
            let rxMod = rxModIdx.flatMap { Int(values[$0]) } ?? 0
            let txMod = txModIdx.flatMap { Int(values[$0]) } ?? 0
            
            let channel = Channel(
                channelID: index, // Will be overwritten when saved to correct slot
                txMod: ModulationType(rawValue: txMod == 1 ? "AM" : "FM") ?? .fm,
                txFreq: txFreq,
                rxMod: ModulationType(rawValue: rxMod == 1 ? "AM" : "FM") ?? .fm,
                rxFreq: rxFreq,
                txSubAudio: txSubAudio,
                rxSubAudio: rxSubAudio,
                scan: scan == 1,
                txAtMaxPower: txPower == "HIGH",
                talkAround: talkAround == 1,
                bandwidth: BandwidthType(rawValue: bandwidth == 1 ? "WIDE" : "NARROW") ?? .wide,
                preDeEmphBypass: preDeEmph == 1,
                sign: sign == 1,
                txAtMedPower: txPower == "MED",
                txDisable: txDis == 1,
                fixedFreq: false,
                fixedBandwidth: false,
                fixedTxPower: false,
                mute: mute == 1,
                name: String(name.prefix(10))
            )
            
            channels.append(channel)
        }
        
        guard !channels.isEmpty else {
            throw CSVImportError.invalidFormat("No valid channels found in file")
        }
        
        return channels
    }
    
    private func parseSubAudio(_ value: String) -> SubAudio? {
        guard let freq = Double(value), freq > 0 else {
            return nil
        }
        return .frequency(freq)
    }
}

private struct ChannelRowView: View {
    let channel: Channel
    var isVFO: Bool = false

    private var title: String {
        if !channel.name.isEmpty {
            return channel.name
        }
        if isVFO {
            return channel.channelID == 252 ? "VFO A" : "VFO B"
        }
        return "Channel \(channel.channelID + 1)"
    }

    private var frequencyText: String {
        String(format: "%.5f MHz", channel.rxFreq)
    }

    private var badgeText: String {
        isVFO ? "VFO" : String(format: "%03d", channel.channelID + 1)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(badgeText)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(isVFO ? Color.blue.opacity(0.15) : Color.gray.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(frequencyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if channel.txDisable {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

enum CSVImportError: LocalizedError {
    case invalidFormat(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat(let message):
            return message
        }
    }
}
