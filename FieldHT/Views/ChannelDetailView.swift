//
//  ChannelDetailView.swift
//  FieldHT
//
//  Created by Benjamin Faershtein on 12/14/25.
//

import SwiftUI

struct ChannelDetailView: View {
    let channel: Channel
    @ObservedObject var viewModel: ChannelViewModel
    
    @State private var name: String
    @State private var rxFreq: String
    @State private var txFreq: String
    @State private var txMod: ModulationType
    @State private var bandwidth: BandwidthType
    @State private var scan: Bool
    @State private var talkAround: Bool
    @State private var txDisable: Bool
    @State private var mute: Bool
    @State private var txPowerHigh: Bool
    @State private var rxSubAudio: SubAudio?
    @State private var txSubAudio: SubAudio?
    
    // Track if user has manually edited each field
    @State private var hasEditedRx = false
    @State private var hasEditedTx = false
    
    // Autofill state
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var showAutofillPrompt = false
    @State private var isAutofilling = false
    @State private var autofillError: String?
    
    // Focus states
    @FocusState private var rxFieldFocused: Bool
    @FocusState private var txFieldFocused: Bool
    
    private let repeaterBookService = RepeaterBookService()
    
    // Initializer to populate state from channel
    init(channel: Channel, viewModel: ChannelViewModel) {
        self.channel = channel
        self.viewModel = viewModel
        
        _name = State(initialValue: channel.name)
        _rxFreq = State(initialValue: String(format: "%.5f", channel.rxFreq))
        _txFreq = State(initialValue: String(format: "%.5f", channel.txFreq))
        _txMod = State(initialValue: channel.txMod)
        _bandwidth = State(initialValue: channel.bandwidth)
        _scan = State(initialValue: channel.scan)
        _talkAround = State(initialValue: channel.talkAround)
        _txDisable = State(initialValue: channel.txDisable)
        _mute = State(initialValue: channel.mute)
        _txPowerHigh = State(initialValue: channel.txAtMaxPower)
        _rxSubAudio = State(initialValue: channel.rxSubAudio)
        _txSubAudio = State(initialValue: channel.txSubAudio)
        
        // Check if frequencies are at default (0.00000)
        let rxIsDefault = channel.rxFreq == 0.0
        let txIsDefault = channel.txFreq == 0.0
        _hasEditedRx = State(initialValue: !rxIsDefault)
        _hasEditedTx = State(initialValue: !txIsDefault)
    }
    
    var body: some View {
        Form {
            Section(header: Text("Basic Info")) {
                HStack {
                    Text("Name")
                    Spacer()
                    TextField("Name", text: $name)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: name) { _, newValue in
                             if newValue.count > 10 {
                                 name = String(newValue.prefix(10))
                             }
                             // Check if this looks like a callsign and channel is empty
                             checkForAutofill(callsign: newValue)
                        }
                }
                
                // Autofill prompt
                if showAutofillPrompt && !isAutofilling {
                    HStack {
                        Image(systemName: "wand.and.stars")
                            .foregroundColor(.blue)
                        Text("Autofill from RepeaterBook?")
                            .font(.caption)
                        Spacer()
                        Button("Yes") {
                            autofillFromRepeaterBook()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        Button("No") {
                            showAutofillPrompt = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
                
                if isAutofilling {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Fetching repeater details...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                if let error = autofillError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                HStack {
                    Text("RX Frequency")
                    Spacer()
                    TextField("MHz", text: $rxFreq)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($rxFieldFocused)
                        .onChange(of: rxFieldFocused) { _, isFocused in
                            if !isFocused {
                                // User dismissed keyboard
                                hasEditedRx = true
                                // If TX hasn't been manually edited, sync it with RX
                                if !hasEditedTx {
                                    txFreq = rxFreq
                                }
                            }
                        }
                }
                
                HStack {
                    Text("TX Frequency")
                    Spacer()
                    TextField("MHz", text: $txFreq)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($txFieldFocused)
                        .onChange(of: txFieldFocused) { _, isFocused in
                            if !isFocused {
                                // User dismissed keyboard
                                hasEditedTx = true
                                // If RX hasn't been manually edited, sync it with TX
                                if !hasEditedRx {
                                    rxFreq = txFreq
                                }
                            }
                        }
                }
            }
            
            Section(header: Text("Configuration")) {
                Picker("TX Modulation", selection: $txMod) {
                    ForEach(viewModel.supportsDMR ? ModulationType.allCases : [.fm, .am], id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                
                Picker("Bandwidth", selection: $bandwidth) {
                    ForEach(BandwidthType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                
                Toggle("High Power", isOn: $txPowerHigh)
            }

            Section(header: Text("Tones (Sub-Audio)")) {
                ctcssPicker(label: "RX Tone", selection: $rxSubAudio)
                ctcssPicker(label: "TX Tone", selection: $txSubAudio)
            }
            
            Section(header: Text("Flags")) {
                Toggle("Scan", isOn: $scan)
                Toggle("Talk Around", isOn: $talkAround)
                Toggle("TX Disable", isOn: $txDisable)
                Toggle("Mute", isOn: $mute)
            }
            
            Section {
                Button(action: saveChannel) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Text("Save Changes")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.blue)
                    }
                }
                .disabled(viewModel.isSaving)
            }
        }
        .scrollDismissesKeyboard(ScrollDismissesKeyboardMode.immediately)
        .navigationTitle("Channel \(channel.channelID + 1)")
    }

    private let ctcssFrequencies: [Double] = [
        67.0, 69.3, 71.9, 74.4, 77.0, 79.7, 82.5, 85.4, 88.5, 91.5, 94.8, 97.4, 100.0, 
        103.5, 107.2, 110.9, 114.8, 118.8, 123.0, 127.3, 131.8, 136.5, 141.3, 146.2, 
        151.4, 156.7, 159.8, 162.2, 165.5, 167.9, 171.3, 173.8, 177.3, 179.9, 183.5, 
        186.2, 189.9, 192.8, 196.6, 199.5, 203.5, 206.5, 210.7, 218.1, 225.7, 229.1, 
        233.6, 241.8, 250.3, 254.1
    ]

    @ViewBuilder
    private func ctcssPicker(label: String, selection: Binding<SubAudio?>) -> some View {
        Picker(label, selection: selection) {
            Text("None").tag(SubAudio?.none)
            ForEach(ctcssFrequencies, id: \.self) { freq in
                Text(String(format: "%.1f Hz", freq)).tag(SubAudio?.some(.frequency(freq)))
            }
        }
    }
    
    
    private func saveChannel() {
        guard let rx = Double(rxFreq), let tx = Double(txFreq) else {
            // TODO: Show validation error
            return
        }
        
        // Reconstruct channel with new values
        let updatedChannel = Channel(
            channelID: channel.channelID,
            txMod: txMod, 
            txFreq: tx,
            rxMod: txMod, 
            rxFreq: rx,
            txSubAudio: txSubAudio,
            rxSubAudio: rxSubAudio,
            scan: scan,
            txAtMaxPower: txPowerHigh,
            talkAround: talkAround,
            bandwidth: bandwidth,
            preDeEmphBypass: channel.preDeEmphBypass,
            sign: channel.sign,
            txAtMedPower: !txPowerHigh, 
            txDisable: txDisable,
            fixedFreq: channel.fixedFreq,
            fixedBandwidth: channel.fixedBandwidth,
            fixedTxPower: channel.fixedTxPower,
            mute: mute,
            name: name
        )
        
        viewModel.updateChannel(updatedChannel)
    }
    
    // MARK: - Autofill Functions
    
    /// Check if the entered text looks like a valid callsign and show autofill prompt
    private func checkForAutofill(callsign: String) {
        // Only show prompt if:
        // 1. Channel is empty (rxFreq == 0.0)
        // 2. Name looks like a valid callsign
        // 3. Internet is available
        // 4. We haven't already shown the prompt for this callsign
        
        let isEmptyChannel = channel.rxFreq == 0.0 && channel.txFreq == 0.0
        let isValidCallsign = isValidCallsignFormat(callsign)
        let hasInternet = networkMonitor.isConnected
        
        if isEmptyChannel && isValidCallsign && hasInternet && !showAutofillPrompt {
            showAutofillPrompt = true
            autofillError = nil
        } else if !isValidCallsign || !hasInternet {
            showAutofillPrompt = false
        }
    }
    
    /// Validate if text looks like a valid callsign format
    /// Basic validation: 3-7 characters, alphanumeric, typically starts with letter/number
    private func isValidCallsignFormat(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces).uppercased()
        // Callsigns are typically 3-7 characters, alphanumeric
        // Common formats: W1AW, K1ABC, N0XYZ, etc.
        guard trimmed.count >= 3 && trimmed.count <= 7 else {
            return false
        }
        
        // Must be alphanumeric
        let alphanumeric = CharacterSet.alphanumerics
        guard trimmed.unicodeScalars.allSatisfy({ alphanumeric.contains($0) }) else {
            return false
        }
        
        // Typically starts with a letter or number
        let firstChar = trimmed.first!
        return firstChar.isLetter || firstChar.isNumber
    }
    
    /// Autofill channel details from RepeaterBook
    private func autofillFromRepeaterBook() {
        guard networkMonitor.isConnected else {
            autofillError = "No internet connection"
            showAutofillPrompt = false
            return
        }
        
        let callsign = name.trimmingCharacters(in: .whitespaces).uppercased()
        guard isValidCallsignFormat(callsign) else {
            autofillError = "Invalid callsign format"
            showAutofillPrompt = false
            return
        }
        
        isAutofilling = true
        showAutofillPrompt = false
        autofillError = nil
        
        Task {
            do {
                let results = try await repeaterBookService.searchByCallsign(callsign)
                
                await MainActor.run {
                    isAutofilling = false
                    
                    guard let firstResult = results.first else {
                        autofillError = "No repeater found for \(callsign)"
                        return
                    }
                    
                    // Populate channel fields from first result
                    if let rxFreqMHz = firstResult.frequencyMHz {
                        rxFreq = String(format: "%.5f", rxFreqMHz)
                        hasEditedRx = true
                    }
                    
                    if let txFreqMHz = firstResult.inputFreqMHz {
                        txFreq = String(format: "%.5f", txFreqMHz)
                        hasEditedTx = true
                    } else {
                        // If no input freq, use output freq for TX (simplex)
                        if let rxFreqMHz = firstResult.frequencyMHz {
                            txFreq = String(format: "%.5f", rxFreqMHz)
                            hasEditedTx = true
                        }
                    }
                    
                    // Set CTCSS tone if available
                    if let subAudio = firstResult.subAudio {
                        rxSubAudio = subAudio
                        txSubAudio = subAudio
                    }
                    
                    // Set modulation to FM (most repeaters are FM)
                    txMod = .fm
                    
                    // Set bandwidth to wide (typical for repeaters)
                    bandwidth = .wide
                    
                    // High power
                    txPowerHigh = true
                    
                    
                    
                    // Update name to callsign if not already set
                    if name.isEmpty || name == callsign {
                        name = callsign
                    }
                    
                    // If multiple results found, show a note
                    if results.count > 1 {
                        autofillError = "Found \(results.count) repeaters, using first result"
                    }
                }
            } catch {
                await MainActor.run {
                    isAutofilling = false
                    autofillError = "Failed to fetch: \(error.localizedDescription)"
                }
            }
        }
    }
}
