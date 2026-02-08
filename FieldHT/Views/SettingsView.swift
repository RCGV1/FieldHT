//
//  SettingsView.swift
//  FieldHT
//
//  Created by Benjamin Faershtein on 12/13/25.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var radioManager: RadioManager
    @StateObject private var viewModel = SettingsViewModel()
    
    @State private var isHydrating = false

    private var isSyncDisabled: Bool {
        !radioManager.isConnected || isHydrating || viewModel.isSaving || viewModel.isLoading
    }
    
    var body: some View {
        ZStack {
            Group {
                if !radioManager.isConnected {
                    ContentUnavailableView {
                        Label("Not Connected", systemImage: "antenna.radiowaves.left.and.right.slash")
                    } description: {
                        Text("Connect to a radio device to view and edit settings")
                    }
                } else if viewModel.isLoading {
                    ProgressView("Loading settings...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.settings != nil {
                    Form {
                        Section {
                            if let radioController = radioManager.radioController {
                                NavigationLink {
                                    ChannelListView(radioController: radioController)
                                        .environmentObject(radioManager)
                                } label: {
                                    Label("Channels & Memory Groups", systemImage: "list.number")
                                }

                                NavigationLink {
                                    PFSettingsView(radioController: radioController, viewModel: viewModel)
                                } label: {
                                    Label("Programmable Buttons", systemImage: "button.programmable")
                                }
                            } else {
                                Label("Channels & Memory Groups", systemImage: "list.number")
                                    .foregroundColor(.secondary)
                                Label("Programmable Buttons", systemImage: "button.programmable")
                                    .foregroundColor(.secondary)
                            }
                        } header: {
                            Label("Configuration", systemImage: "gearshape.2")
                        }

                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("Squelch", systemImage: "speaker.wave.2")
                                    Spacer()
                                    Text("\(viewModel.settings?.squelchLevel ?? 0)")
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)
                                }
                                Slider(
                                    value: Binding(
                                        get: { Double(viewModel.settings?.squelchLevel ?? 0) },
                                        set: { viewModel.updateSquelchLevel(Int($0)) }
                                    ),
                                    in: 0...9,
                                    step: 1
                                )
                            }

                            Picker(
                                selection: Binding(
                                    get: { viewModel.settings?.micGain ?? 0 },
                                    set: { viewModel.updateMicGain($0) }
                                )
                            ) {
                                ForEach(0..<5) { i in
                                    Text("\(i)").tag(i)
                                }
                            } label: {
                                Label("Mic Gain", systemImage: "mic")
                            }

                            Picker(
                                selection: Binding(
                                    get: { viewModel.settings?.btMicGain ?? 0 },
                                    set: { viewModel.updateBtMicGain($0) }
                                )
                            ) {
                                ForEach(0..<5) { i in
                                    Text("\(i)").tag(i)
                                }
                            } label: {
                                Label("BT Mic Gain", systemImage: "mic.and.signal.meter")
                            }

                            Picker(
                                selection: Binding(
                                    get: { viewModel.settings?.localSpeaker ?? 0 },
                                    set: { viewModel.updateLocalSpeaker($0) }
                                )
                            ) {
                                Text("Internal").tag(0)
                                Text("External").tag(1)
                                Text("Both").tag(2)
                            } label: {
                                Label("Local Speaker", systemImage: "speaker")
                            }

                            Picker(
                                selection: Binding(
                                    get: { viewModel.settings?.hmSpeaker ?? 0 },
                                    set: { viewModel.updateHmSpeaker($0) }
                                )
                            ) {
                                Text("Off").tag(0)
                                Text("On").tag(1)
                            } label: {
                                Label("HM Speaker", systemImage: "speaker.wave.3")
                            }
                        } header: {
                            Label("Audio", systemImage: "speaker.wave.2")
                        }

                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("TX Hold", systemImage: "timer")
                                    Spacer()
                                    Text("\(viewModel.settings?.txHoldTime ?? 0)s")
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)
                                }
                                Slider(
                                    value: Binding(
                                        get: { Double(viewModel.settings?.txHoldTime ?? 0) },
                                        set: { viewModel.updateTxHoldTime(Int($0)) }
                                    ),
                                    in: 0...10,
                                    step: 1
                                )
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("TX Limit", systemImage: "hourglass")
                                    Spacer()
                                    Text("\(viewModel.settings?.txTimeLimit ?? 0)s")
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)
                                }
                                Slider(
                                    value: Binding(
                                        get: { Double(viewModel.settings?.txTimeLimit ?? 0) },
                                        set: { viewModel.updateTxTimeLimit(Int($0)) }
                                    ),
                                    in: 0...240,
                                    step: 30
                                )
                            }

                            Toggle(
                                isOn: Binding(
                                    get: { viewModel.settings?.tailElim ?? false },
                                    set: { viewModel.updateTailElim($0) }
                                )
                            ) {
                                Label("Tail Eliminator", systemImage: "waveform.path")
                            }

                            Toggle(
                                isOn: Binding(
                                    get: { viewModel.settings?.pttLock ?? false },
                                    set: { viewModel.updatePttLock($0) }
                                )
                            ) {
                                Label("PTT Lock", systemImage: "lock")
                            }

                            Toggle(
                                isOn: Binding(
                                    get: { viewModel.isDualWatchOn },
                                    set: { viewModel.setDualWatch($0) }
                                )
                            ) {
                                Label("Dual Watch", systemImage: "rectangle.split.2x1")
                            }
                        } header: {
                            Label("Transmission", systemImage: "antenna.radiowaves.left.and.right")
                        }

                        Section {
                            Toggle(
                                isOn: Binding(
                                    get: { viewModel.settings?.autoPowerOn ?? false },
                                    set: { viewModel.updateAutoPowerOn($0) }
                                )
                            ) {
                                Label("Auto Power On", systemImage: "power")
                            }

                            Picker(
                                selection: Binding(
                                    get: { viewModel.settings?.autoPowerOff ?? 0 },
                                    set: { viewModel.updateAutoPowerOff($0) }
                                )
                            ) {
                                Text("Off").tag(0)
                                Text("Level 1 (Short)").tag(1)
                                Text("Level 2").tag(2)
                                Text("Level 3").tag(3)
                                Text("Level 4 (Medium)").tag(4)
                                Text("Level 5").tag(5)
                                Text("Level 6").tag(6)
                                Text("Level 7 (Long)").tag(7)
                            } label: {
                                Label("Auto Power Off", systemImage: "powersleep")
                            }

                            Toggle(
                                isOn: Binding(
                                    get: { viewModel.settings?.powerSavingMode ?? false },
                                    set: { viewModel.updatePowerSavingMode($0) }
                                )
                            ) {
                                Label("Power Saving", systemImage: "leaf")
                            }
                        } header: {
                            Label("Power", systemImage: "bolt")
                        }

                        Section {
                            Picker(
                                selection: Binding(
                                    get: { viewModel.settings?.screenTimeout ?? 0 },
                                    set: { viewModel.updateScreenTimeout($0) }
                                )
                            ) {
                                Text("Always On").tag(31)
                                Text("5s").tag(5)
                                Text("10s").tag(10)
                                Text("15s").tag(15)
                                Text("20s").tag(20)
                                Text("25s").tag(25)
                                Text("300s (Max)").tag(300)
                            } label: {
                                Label("Screen Timeout", systemImage: "display")
                            }

                            Toggle(
                                isOn: Binding(
                                    get: { viewModel.settings?.imperialUnit ?? false },
                                    set: { viewModel.updateImperialUnit($0) }
                                )
                            ) {
                                Label("Imperial Units", systemImage: "ruler")
                            }
                        } header: {
                            Label("Display", systemImage: "display")
                        }

                        Section {
                            Toggle(
                                isOn: Binding(
                                    get: { viewModel.settings?.autoRelayEn ?? false },
                                    set: { viewModel.updateAutoRelayEn($0) }
                                )
                            ) {
                                Label("Auto Relay", systemImage: "arrow.triangle.2.circlepath")
                            }

                            Toggle(
                                isOn: Binding(
                                    get: { viewModel.settings?.keepAghfpLink ?? false },
                                    set: { viewModel.updateKeepAghfpLink($0) }
                                )
                            ) {
                                Label("Keep AGHFP Link", systemImage: "link")
                            }

                            Toggle(
                                isOn: Binding(
                                    get: { viewModel.settings?.adaptiveResponse ?? false },
                                    set: { viewModel.updateAdaptiveResponse($0) }
                                )
                            ) {
                                Label("Adaptive Response", systemImage: "sparkles")
                            }

                            Toggle(
                                isOn: Binding(
                                    get: { viewModel.settings?.disTone ?? false },
                                    set: { viewModel.updateDisTone($0) }
                                )
                            ) {
                                Label("Disable Tone", systemImage: "speaker.slash")
                            }

                            Toggle(
                                isOn: Binding(
                                    get: { viewModel.settings?.useFreqRange2 ?? false },
                                    set: { viewModel.updateUseFreqRange2($0) }
                                )
                            ) {
                                Label("Use Freq Range 2", systemImage: "wave.3.right")
                            }

                            Toggle(
                                isOn: Binding(
                                    get: { viewModel.settings?.leadingSyncBitEn ?? false },
                                    set: { viewModel.updateLeadingSyncBitEn($0) }
                                )
                            ) {
                                Label("Leading Sync Bit", systemImage: "waveform")
                            }

                            Toggle(
                                isOn: Binding(
                                    get: { viewModel.settings?.pairingAtPowerOn ?? false },
                                    set: { viewModel.updatePairingAtPowerOn($0) }
                                )
                            ) {
                                Label("Pairing at Power On", systemImage: "dot.radiowaves.left.and.right")
                            }

                            Toggle(
                                isOn: Binding(
                                    get: { viewModel.settings?.disDigitalMute ?? false },
                                    set: { viewModel.updateDisDigitalMute($0) }
                                )
                            ) {
                                Label("Disable Digital Mute", systemImage: "speaker.slash.circle")
                            }

                            Toggle(
                                isOn: Binding(
                                    get: { viewModel.settings?.signalingEccEn ?? false },
                                    set: { viewModel.updateSignalingEccEn($0) }
                                )
                            ) {
                                Label("Signaling ECC", systemImage: "checkmark.shield")
                            }

                            Toggle(
                                isOn: Binding(
                                    get: { viewModel.settings?.chDataLock ?? false },
                                    set: { viewModel.updateChDataLock($0) }
                                )
                            ) {
                                Label("Channel Data Lock", systemImage: "lock.doc")
                            }
                        } header: {
                            Label("Advanced", systemImage: "wrench.and.screwdriver")
                        }
                    }
                    .disabled(viewModel.isSaving || isHydrating)
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundColor(.red)
                        Text("Error Loading Settings")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button("Retry") {
                            viewModel.retryLoad()
                        }
                        .padding(.top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        Text("Status Unknown")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Connected explicitly but no settings data available.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Force Reload") {
                            viewModel.retryLoad()
                        }
                        .padding(.top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .blur(radius: isHydrating ? 3 : 0)

            if isHydrating {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))

                        Text("Syncing with radio...")
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
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isSaving {
                    ProgressView()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await hydrateRadio() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .disabled(isSyncDisabled)
                .accessibilityLabel("Sync")
            }
        }
        .onChange(of: radioManager.isConnected) { _, isConnected in
            if isConnected {
                Task {
                    await hydrateRadio()
                }
            } else {
                viewModel.setRadioController(nil)
            }
        }
        .onAppear {
            print("SettingsView: onAppear. Connected: \(radioManager.isConnected)")
            if radioManager.isConnected {
                viewModel.setRadioController(radioManager.radioController)
            }
        }
    }
    
    // Helper function to hydrate radio with loading indicator and retry logic
    private func hydrateRadio() async {
        await MainActor.run {
            isHydrating = true
        }
        
        // Give time for radio to complete initial hydration if just connected
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        let backoffs = [5, 10, 15]
        
        for attempt in 0..<3 {
            do {
                try await radioManager.radioController?.hydrate()
                
                await MainActor.run {
                    if radioManager.isConnected {
                        viewModel.setRadioController(radioManager.radioController)
                    }
                    isHydrating = false
                }
                return // Success
            } catch {
                print("Settings hydration attempt \(attempt + 1) failed: \(error)")
                
                if attempt < backoffs.count {
                    let delaySeconds = backoffs[attempt]
                    let delay = UInt64(delaySeconds) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
        
        await MainActor.run {
            isHydrating = false
            viewModel.errorMessage = "Failed to sync settings with radio after multiple attempts."
        }
    }
}

// Helper view for editable setting rows
struct SettingRow: View {
    let title: String
    @State var value: String
    let onChange: (String) -> Void
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("Value", text: $value)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
                .onChange(of: value) { _, newValue in
                    onChange(newValue)
                }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(RadioManager())
}
