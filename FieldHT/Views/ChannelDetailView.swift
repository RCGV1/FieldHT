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
    
    // Focus states
    @FocusState private var rxFieldFocused: Bool
    @FocusState private var txFieldFocused: Bool
    
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
                        }
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
}
