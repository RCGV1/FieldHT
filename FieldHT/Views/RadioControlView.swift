//
//  RadioControlView.swift
//  FieldHT
//
//  Created by Benjamin Faershtein on 12/14/25.
//

import SwiftUI

struct RadioControlView: View {
    @EnvironmentObject var radioManager: RadioManager
    @State private var localSquelchLevel: Int = 0
    @StateObject private var viewModel = ChannelViewModel()



    // MARK: - RSSI Configuration
    private let minRSSI: Double = -120
    private let maxRSSI: Double = 0

    private var clampedRSSI: Double {
        min(max(Double(radioManager.rssi), minRSSI), maxRSSI)
    }

    private var rssiColor: Color {
        if radioManager.rssi >= -60 {
            return .green
        } else if radioManager.rssi >= -90 {
            return .yellow
        } else {
            return .red
        }
    }

    private func memoryGroupDisplayName(index: Int) -> String {
        guard index >= 0, index < radioManager.regionNames.count else {
            return "Unnamed"
        }

        let raw = radioManager.regionNames[index].trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            return "Unnamed"
        }

        return raw
    }

    @ViewBuilder
    private var memoryGroupSection: some View {
        VStack(alignment: .leading) {
            Text("Memory Group")
                .font(.headline)

            if radioManager.isConnected, !radioManager.regionNames.isEmpty {
                Picker(selection: Binding(
                    get: { radioManager.activeRegionIndex },
                    set: { radioManager.setRegion($0) }
                )) {
                    ForEach(0..<radioManager.regionNames.count, id: \.self) { index in
                        Text("\(index + 1).  \(memoryGroupDisplayName(index: index))").tag(index)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text("\(radioManager.activeRegionIndex + 1).")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.06))
                            .clipShape(Capsule())

                        Text(memoryGroupDisplayName(index: radioManager.activeRegionIndex))
                            .font(.headline)
                            .lineLimit(1)

                        Spacer(minLength: 12)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
                .cornerRadius(12)
            } else {
                HStack(spacing: 10) {
                    Text("--.")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.06))
                        .clipShape(Capsule())

                    if radioManager.isConnected {
                        ProgressView()
                        Text("Loading memory groups...")
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Connect to load memory groups")
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
                .cornerRadius(12)
            }
        }
    }

    @ViewBuilder
    private var vfoSection: some View {
        if radioManager.isDualWatchOn {
            HStack(spacing: 16) {
                VFOControl(
                    title: "Channel A",
                    channelIndex: radioManager.vfoAIndex,
                    viewModel: viewModel,
                    isActive: radioManager.activeChannel == .a,
                    isVFO: radioManager.isVFOA,
                    vfoFrequency: radioManager.vfoAFrequencyMHz,
                    vfoChannel: radioManager.vfoAChannel,
                    onSelect: { radioManager.setChannelA($0) },
                    onTap: { radioManager.switchActiveChannel(to: .a) },
                    onToggleVFO: { radioManager.toggleVFO(for: .a) },
                    onUpdateChannel: { radioManager.updateChannel($0) }
                )

                VFOControl(
                    title: "Channel B",
                    channelIndex: radioManager.vfoBIndex,
                    viewModel: viewModel,
                    isActive: radioManager.activeChannel == .b,
                    isVFO: radioManager.isVFOB,
                    vfoFrequency: radioManager.vfoBFrequencyMHz,
                    vfoChannel: radioManager.vfoBChannel,
                    onSelect: { radioManager.setChannelB($0) },
                    onTap: { radioManager.switchActiveChannel(to: .b) },
                    onToggleVFO: { radioManager.toggleVFO(for: .b) },
                    onUpdateChannel: { radioManager.updateChannel($0) }
                )
            }
        } else {
            VFOControl(
                title: "Channel A",
                channelIndex: radioManager.vfoAIndex,
                viewModel: viewModel,
                isActive: true,
                isVFO: radioManager.isVFOA,
                vfoFrequency: radioManager.vfoAFrequencyMHz,
                vfoChannel: radioManager.vfoAChannel,
                onSelect: { radioManager.setChannelA($0) },
                onTap: { radioManager.switchActiveChannel(to: .a) },
                onToggleVFO: { radioManager.toggleVFO(for: .a) },
                onUpdateChannel: { radioManager.updateChannel($0) }
            )
            .frame(maxWidth: .infinity)
        }
    }

    private var channelNavigationSection: some View {
        HStack(spacing: 40) {
            Button(action: previousChannel) {
                Image(systemName: "arrowshape.backward.fill")
                    .font(.system(size: 44))
            }
            .disabled(validChannels.isEmpty)

            Button(action: nextChannel) {
                Image(systemName: "arrowshape.forward.fill")
                    .font(.system(size: 44))
            }
            .disabled(validChannels.isEmpty)
        }
    }

    private var squelchSection: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Squelch Level")
                    .font(.headline)
                Spacer()
                Text("\(localSquelchLevel)")
                    .font(.title3)
                    .bold()
            }

            Slider(
                value: Binding(
                    get: { Double(localSquelchLevel) },
                    set: { localSquelchLevel = Int($0) }
                ),
                in: 0...9,
                step: 1,
                onEditingChanged: { editing in
                    if !editing {
                        radioManager.setSquelch(localSquelchLevel)
                    }
                }
            )
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var rssiGaugeSection: some View {
        VStack(alignment: .leading) {
            RSSILinearGauge(rssi: radioManager.rssi)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var connectionBanner: some View {
        if !radioManager.isConnected {
            Text("Radio not connected")
                .font(.title)
                .foregroundColor(.secondary)
                .padding()
        }
    }

    private var mainContent: some View {
        VStack(spacing: 20) {
            connectionBanner

            // MARK: - Memory Group
            memoryGroupSection

            // MARK: - Dual Monitor Toggle (Left-Aligned)
            dualMonitorToggle

            // MARK: - VFO Section
            vfoSection

            // MARK: - Quick Toggles
            quickTogglesSection

            // MARK: - Channel Navigation
            channelNavigationSection

            // MARK: - Squelch
            squelchSection

            // MARK: - RSSI Gauge
            rssiGaugeSection

            // MARK: - Amateur Satellite Tracking
            NavigationLink {
                SatelliteTrackingView()
                    .environmentObject(radioManager)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Amateur Satellite")
                            .font(.headline)
                        Text("Map + next pass + Doppler")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }

            Spacer()
        }
        .padding()
    }

    private func currentActiveChannelForTalkAround() -> Channel? {
        guard let controller = radioManager.radioController else { return nil }

        let active = radioManager.activeChannel
        let channelID: Int

        switch active {
        case .a:
            channelID = radioManager.isVFOA ? 252 : radioManager.vfoAIndex
        case .b:
            channelID = radioManager.isVFOB ? 251 : radioManager.vfoBIndex
        case .off:
            // If dual watch is off we treat A as active.
            channelID = radioManager.isVFOA ? 252 : radioManager.vfoAIndex
        }

        return controller.channelsForCurrentRegion.first(where: { $0.channelID == channelID })
    }

    private var quickTogglesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Toggles")
                .font(.headline)

            Toggle(
                isOn: Binding(
                    get: { currentActiveChannelForTalkAround()?.talkAround ?? false },
                    set: { newValue in
                        guard var channel = currentActiveChannelForTalkAround() else { return }
                        channel.talkAround = newValue
                        radioManager.updateChannel(channel)
                    }
                )
            ) {
                Label("Talk Around", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!radioManager.isConnected || radioManager.isBusy || currentActiveChannelForTalkAround() == nil)
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
    }

    private var dualMonitorToggle: some View {
        HStack {
            Button {
                radioManager.setDualWatch(!radioManager.isDualWatchOn)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: radioManager.isDualWatchOn
                          ? "rectangle.split.2x1.fill"
                          : "rectangle")
                        .font(.headline)

                    Text("Dual Monitor")
                        .font(.headline)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundColor(radioManager.isDualWatchOn ? .green : .primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            radioManager.isDualWatchOn ? Color.green : Color.secondary,
                            lineWidth: 2
                        )
                )
            }

            Spacer()
        }
    }

    var body: some View {
        ScrollView {
            mainContent
        }
        .navigationTitle("Radio Control")
        .disabled(radioManager.isBusy)
        .onAppear {
            localSquelchLevel = radioManager.squelchLevel
            viewModel.setRadioController(radioManager.radioController)
            
            // Only hydrate if we don't have state yet or if coming from a fresh appear
            if radioManager.isConnected && radioManager.radioController?.state != nil {
                viewModel.loadChannels()
            } else {
                Task {
                    try? await radioManager.radioController?.hydrate()
                    viewModel.loadChannels()
                }
            }
        }
        .onChange(of: radioManager.activeRegionIndex) { oldVal, newVal in
            if oldVal != newVal {
                viewModel.loadChannels()
            }
        }
        .onChange(of: radioManager.squelchLevel) {
            localSquelchLevel = $0
        }
    }


    // MARK: - Channel Navigation Helpers

    private var validChannels: [Int] {
        radioManager.channels.enumerated()
            .filter { $0.element.rxFreq != 0.0 }
            .map { $0.offset }
    }

    private var activeChannelIndex: Int {
        radioManager.activeChannel == .a
        ? radioManager.vfoAIndex
        : radioManager.vfoBIndex
    }

    private func previousChannel() {
        guard !validChannels.isEmpty else { return }
        let current = activeChannelIndex
        guard let pos = validChannels.firstIndex(of: current) else {
            setActiveChannel(validChannels.last!)
            return
        }
        let newPos = pos == 0 ? validChannels.count - 1 : pos - 1
        setActiveChannel(validChannels[newPos])
    }

    private func nextChannel() {
        guard !validChannels.isEmpty else { return }
        let current = activeChannelIndex
        guard let pos = validChannels.firstIndex(of: current) else {
            setActiveChannel(validChannels.first!)
            return
        }
        let newPos = pos == validChannels.count - 1 ? 0 : pos + 1
        setActiveChannel(validChannels[newPos])
    }

    private func setActiveChannel(_ index: Int) {
        radioManager.activeChannel == .a
        ? radioManager.setChannelA(index)
        : radioManager.setChannelB(index)
    }
}
//
// MARK: - VFO Control
//
struct VFOControl: View {
    let title: String
    let channelIndex: Int
    @ObservedObject var viewModel: ChannelViewModel
    let isActive: Bool
    let isVFO: Bool
    let vfoFrequency: Double
    let vfoChannel: Channel?
    let onSelect: (Int) -> Void
    let onTap: () -> Void
    let onToggleVFO: () -> Void
    let onUpdateChannel: (Channel) -> Void
    
    @State private var showingEditSheet: Bool = false

    private var selectedChannel: Channel? {
        channelIndex < viewModel.channels.count ? viewModel.channels[channelIndex] : nil
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(isActive ? .green : .blue)

                
                Spacer()
                
                Button(action: onToggleVFO) {
                    Text(isVFO ? "MEM" : "VFO")
                        .font(.caption)
                        .bold()
                        .padding(4)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(4)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                if isVFO {
                    Text("VFO Mode")
                        .font(.caption)
                        .foregroundColor(.orange)
                    
                    Text(String(format: "%.5f MHz", vfoFrequency))
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                } else if let channel = selectedChannel {
                    Text(channel.name.isEmpty
                         ? "Channel \(channel.channelID + 1)"
                         : channel.name)
                        .font(.title2)
                        .bold()
                        .lineLimit(1)

                    Text(String(format: "%.5f MHz", channel.rxFreq))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("Unknown")
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }

            Spacer()

            Button(action: { showingEditSheet = true }) {
                Text("Change")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(isVFO ? Color.orange : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .sheet(isPresented: $showingEditSheet) {
                if isVFO, let channel = vfoChannel {
                    VFOEditSheet(channel: channel, onUpdate: onUpdateChannel)
                } else {
                    ChannelSelectionView(
                        viewModel: viewModel,
                        selectedID: channelIndex,
                        onSelect: onSelect
                    )
                }
            }
        }
        .padding()
        .frame(height: 180)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.green : .clear, lineWidth: 3)
        )
    }
}

//
// MARK: - Channel Selection
//
struct ChannelSelectionView: View {
    @ObservedObject var viewModel: ChannelViewModel
    let selectedID: Int
    let onSelect: (Int) -> Void
    
    @Environment(\.presentationMode) private var presentationMode
    
    var body: some View {
        List {

            ForEach(viewModel.channels, id: \.channelID) { channel in
                HStack {
                    Text(String(format: "%03d", channel.channelID + 1))
                        .font(.caption)
                        .monospacedDigit()
                        .padding(4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)

                    VStack(alignment: .leading) {
                        Text(channel.name.isEmpty
                             ? "Channel \(channel.channelID + 1)"
                             : channel.name)
                            .font(.headline)
                        Text(String(format: "%.5f MHz", channel.rxFreq))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if channel.channelID == selectedID {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect(channel.channelID)
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
        .navigationTitle("Select Channel")
    }
}

struct VFOEditSheet: View {
    let channel: Channel
    let onUpdate: (Channel) -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var rxFreqString: String
    @State private var txFreqString: String
    @State private var isSimplex: Bool
    @State private var bandwidth: BandwidthType
    @State private var txPowerMax: Bool
    
    init(channel: Channel, onUpdate: @escaping (Channel) -> Void) {
        self.channel = channel
        self.onUpdate = onUpdate
        _rxFreqString = State(initialValue: String(format: "%.5f", channel.rxFreq))
        _txFreqString = State(initialValue: String(format: "%.5f", channel.txFreq))
        _isSimplex = State(initialValue: abs(channel.rxFreq - channel.txFreq) < 0.00001)
        _bandwidth = State(initialValue: channel.bandwidth)
        _txPowerMax = State(initialValue: channel.txAtMaxPower)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Frequency")) {
                    HStack {
                        Text("RX Freq")
                        Spacer()
                        TextField("145.000", text: $rxFreqString)
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: rxFreqString) { newValue in
                                if isSimplex {
                                    txFreqString = newValue
                                }
                            }
                    }
                    
                    Toggle("Simplex (TX=RX)", isOn: $isSimplex)
                        .onChange(of: isSimplex) { newValue in
                            if newValue {
                                txFreqString = rxFreqString
                            }
                        }
                    
                    if !isSimplex {
                        HStack {
                            Text("TX Freq")
                            Spacer()
                            TextField("145.600", text: $txFreqString)
                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                
                Section(header: Text("Transmission")) {
                    Picker("Bandwidth", selection: $bandwidth) {
                        Text("Narrow (12.5k)").tag(BandwidthType.narrow)
                        Text("Wide (25k)").tag(BandwidthType.wide)
                    }
                    
                    Toggle("High Power", isOn: $txPowerMax)
                }
                
                Section(footer: Text("Changes will be sent to the radio immediately on save.")) {
                     Button("Save Settings") {
                         save()
                     }
                     .frame(maxWidth: .infinity)
                     .foregroundColor(.orange)
                }
            }
            .navigationTitle("VFO Config")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func save() {
        if var rx = Double(rxFreqString), var tx = Double(isSimplex ? rxFreqString : txFreqString) {
            var updated = channel
            updated.rxFreq = rx
            updated.txFreq = tx
            updated.bandwidth = bandwidth
            updated.txAtMaxPower = txPowerMax
            onUpdate(updated)
            dismiss()
        }
    }
}
