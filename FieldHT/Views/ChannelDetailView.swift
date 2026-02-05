//
//  ChannelDetailView.swift
//  FieldHT
//
//  Improved with save-on-dismiss and better SwiftUI styling
//

import SwiftUI

struct ChannelDetailView: View {
    let channel: Channel
    @ObservedObject var viewModel: ChannelViewModel
    @Environment(\.dismiss) private var dismiss
    
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
    
    @State private var hasChanges = false
    @State private var showDiscardAlert = false
    
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var showAutofillPrompt = false
    @State private var isAutofilling = false
    @State private var autofillError: String?
    
    @FocusState private var rxFieldFocused: Bool
    @FocusState private var txFieldFocused: Bool
    @FocusState private var nameFieldFocused: Bool
    
    private let repeaterBookService = RepeaterBookService()
    
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
    }
    
    var body: some View {
        NavigationStack {
            Form {
                basicInfoSection
                configurationSection
                tonesSection
                flagsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Channel \(channel.channelID + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChannel()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasChanges)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .interactiveDismissDisabled(hasChanges)
            .alert("Discard Changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) {
                    dismiss()
                }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("You have unsaved changes.")
            }
            .onChange(of: name) { _, _ in hasChanges = true }
            .onChange(of: rxFreq) { _, _ in hasChanges = true }
            .onChange(of: txFreq) { _, _ in hasChanges = true }
            .onChange(of: txMod) { _, _ in hasChanges = true }
            .onChange(of: bandwidth) { _, _ in hasChanges = true }
            .onChange(of: scan) { _, _ in hasChanges = true }
            .onChange(of: talkAround) { _, _ in hasChanges = true }
            .onChange(of: txDisable) { _, _ in hasChanges = true }
            .onChange(of: mute) { _, _ in hasChanges = true }
            .onChange(of: txPowerHigh) { _, _ in hasChanges = true }
            .onChange(of: rxSubAudio) { _, _ in hasChanges = true }
            .onChange(of: txSubAudio) { _, _ in hasChanges = true }
        }
    }
    
    private var basicInfoSection: some View {
        Section("Basic Info") {
            HStack {
                Text("Name")
                Spacer()
                TextField("Name", text: $name)
                    .multilineTextAlignment(.trailing)
                    .focused($nameFieldFocused)
                    .onChange(of: name) { _, newValue in
                        if newValue.count > 10 {
                            name = String(newValue.prefix(10))
                        }
                        checkForAutofill(callsign: newValue)
                    }
                    .submitLabel(.done)
                    .onSubmit {
                        nameFieldFocused = false
                    }
            }
            
            if showAutofillPrompt && !isAutofilling {
                autofillPrompt
            }
            
            if isAutofilling {
                autofillLoading
            }
            
            if let error = autofillError {
                autofillErrorView(error)
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
                            if !isTXManuallyEdited {
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
                            if !isRXManuallyEdited {
                                rxFreq = txFreq
                            }
                        }
                    }
            }
        }
    }
    
    private var configurationSection: some View {
        Section("Configuration") {
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
    }
    
    private var tonesSection: some View {
        Section("Tones (Sub-Audio)") {
            ctcssPicker(label: "RX Tone", selection: $rxSubAudio)
            ctcssPicker(label: "TX Tone", selection: $txSubAudio)
        }
    }
    
    private var flagsSection: some View {
        Section("Flags") {
            Toggle("Scan", isOn: $scan)
            Toggle("Talk Around", isOn: $talkAround)
            Toggle("TX Disable", isOn: $txDisable)
            Toggle("Mute", isOn: $mute)
        }
    }
    
    private var autofillPrompt: some View {
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
    
    private var autofillLoading: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Fetching repeater details...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private func autofillErrorView(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private var ctcssFrequencies: [Double] {
        [
            67.0, 69.3, 71.9, 74.4, 77.0, 79.7, 82.5, 85.4, 88.5, 91.5, 94.8, 97.4, 100.0,
            103.5, 107.2, 110.9, 114.8, 118.8, 123.0, 127.3, 131.8, 136.5, 141.3, 146.2,
            151.4, 156.7, 159.8, 162.2, 165.5, 167.9, 171.3, 173.8, 177.3, 179.9, 183.5,
            186.2, 189.9, 192.8, 196.6, 199.5, 203.5, 206.5, 210.7, 218.1, 225.7, 229.1,
            233.6, 241.8, 250.3, 254.1
        ]
    }
    
    @ViewBuilder
    private func ctcssPicker(label: String, selection: Binding<SubAudio?>) -> some View {
        Picker(label, selection: selection) {
            Text("None").tag(SubAudio?.none)
            ForEach(ctcssFrequencies, id: \.self) { freq in
                Text(String(format: "%.1f Hz", freq)).tag(SubAudio?.some(.frequency(freq)))
            }
        }
    }
    
    private var isRXManuallyEdited: Bool {
        guard let rx = Double(rxFreq) else { return false }
        return rx != channel.rxFreq
    }
     
    private var isTXManuallyEdited: Bool {
        guard let tx = Double(txFreq) else { return false }
        return tx != channel.txFreq
    }
    
    private func saveChannel() {
        guard let rx = Double(rxFreq), let tx = Double(txFreq) else { return }
        
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
        hasChanges = false
    }
    
    private func checkForAutofill(callsign: String) {
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
    
    private func isValidCallsignFormat(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard trimmed.count >= 3 && trimmed.count <= 7 else { return false }
        
        let alphanumeric = CharacterSet.alphanumerics
        guard trimmed.unicodeScalars.allSatisfy({ alphanumeric.contains($0) }) else { return false }
        
        let firstChar = trimmed.first!
        return firstChar.isLetter || firstChar.isNumber
    }
    
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
                    
                    if let rxFreqMHz = firstResult.frequencyMHz {
                        rxFreq = String(format: "%.5f", rxFreqMHz)
                    }
                    
                    if let txFreqMHz = firstResult.inputFreqMHz {
                        txFreq = String(format: "%.5f", txFreqMHz)
                    } else if let rxFreqMHz = firstResult.frequencyMHz {
                        txFreq = String(format: "%.5f", rxFreqMHz)
                    }
                    
                    if let subAudio = firstResult.subAudio {
                        rxSubAudio = subAudio
                        txSubAudio = subAudio
                    }
                    
                    txMod = .fm
                    bandwidth = .wide
                    txPowerHigh = true
                    
                    if name.isEmpty || name == callsign {
                        name = callsign
                    }
                    
                    if results.count > 1 {
                        autofillError = "Found \(results.count) repeaters, using first result"
                    }
                    hasChanges = true
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
