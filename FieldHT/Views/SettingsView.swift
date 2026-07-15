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

    var body: some View {
        ZStack {
            Group {
                if !radioManager.isConnected {
                    NotConnectedView()
                } else if viewModel.isLoading {
                    ProgressView("Loading settings...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.settings != nil {
                    Form {
                        Section {
                            if let radioController = radioManager.radioController {
                                NavigationLink {
                                    RadioControlCustomizationView()
                                } label: {
                                    Label("Customize Radio Control", systemImage: "rectangle.3.group")
                                }

                                NavigationLink {
                                    ConnectionManagementView()
                                        .environmentObject(radioManager)
                                } label: {
                                    Label("Connection Management", systemImage: "antenna.radiowaves.left.and.right")
                                }

                                NavigationLink {
                                    ChannelListView(radioController: radioController)
                                        .environmentObject(radioManager)
                                } label: {
                                    Label("Channels & Groups", systemImage: "list.number")
                                }

                                NavigationLink {
                                    PFSettingsView(radioController: radioController, viewModel: viewModel)
                                } label: {
                                    Label("Programmable Buttons", systemImage: "button.vertical.left.press")
                                }

                                NavigationLink {
                                    BeaconSettingsView()
                                        .environmentObject(radioManager)
                                } label: {
                                    Label("APRS Settings", systemImage: "location.fill")
                                }

                                NavigationLink {
                                    ScanSettingsView()
                                        .environmentObject(radioManager)
                                } label: {
                                    Label("Scan", systemImage: "dot.radiowaves.left.and.right")
                                }

                                if radioManager.supportsSpeakerMicAccessory || radioManager.isBluetoothAudioConnected || radioManager.speakerMicController != nil || radioManager.lastSpeakerMicDeviceUUID != nil {
                                    NavigationLink {
                                        SpeakerMicView(viewModel: viewModel)
                                            .environmentObject(radioManager)
                                    } label: {
                                        Label("Speaker Mic & BT Audio", systemImage: "mic.badge.plus")
                                    }
                                }
                            } else {
                                Label("Customize Radio Control", systemImage: "rectangle.3.group")
                                    .foregroundColor(.secondary)
                                Label("Connection Management", systemImage: "antenna.radiowaves.left.and.right")
                                    .foregroundColor(.secondary)
                                Label("Channels & Groups", systemImage: "list.number")
                                    .foregroundColor(.secondary)
                                Label("Programmable Buttons", systemImage: "button.programmable")
                                    .foregroundColor(.secondary)
                                Label("APRS Settings", systemImage: "location.fill")
                                    .foregroundColor(.secondary)
                                Label("Scan", systemImage: "dot.radiowaves.left.and.right")
                                    .foregroundColor(.secondary)
                                Label("Speaker Mic & BT Audio", systemImage: "mic.badge.plus")
                                    .foregroundColor(.secondary)
                            }
                        } header: {
                            Label("Radio Setup", systemImage: "gearshape.2")
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
                                ForEach(RadioPresentation.micGainOptions) { option in
                                    Text(option.label).tag(option.value)
                                }
                            } label: {
                                Label("Radio Mic Gain", systemImage: "mic")
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

                        } header: {
                            Label("Audio", systemImage: "speaker.wave.2")
                        } footer: {
                            if radioManager.supportsSpeakerMicAccessory || radioManager.isBluetoothAudioConnected || radioManager.speakerMicController != nil || radioManager.lastSpeakerMicDeviceUUID != nil {
                                Text("Speaker-mic routing, battery, and Bluetooth audio controls are in Speaker Mic & BT Audio.")
                            }
                        }

                        if radioManager.radioController?.deviceInfo.supportsNOAA == true {
                            Section {
                                Picker(
                                    selection: Binding(
                                        get: { viewModel.settings?.wxMode ?? 0 },
                                        set: { viewModel.updateWxMode($0) }
                                    )
                                ) {
                                    Text("Off").tag(0)
                                    Text("Monitor").tag(1)
                                    Text("Alert").tag(2)
                                } label: {
                                    Label("Weather Mode", systemImage: "cloud.sun")
                                }

                                Picker(
                                    selection: Binding(
                                        get: { viewModel.settings?.noaaCh ?? 0 },
                                        set: { viewModel.updateNoaaCh($0) }
                                    )
                                ) {
                                    ForEach(0..<10) { i in
                                        Text("NOAA \(i + 1)").tag(i)
                                    }
                                } label: {
                                    Label("NOAA Channel", systemImage: "antenna.radiowaves.left.and.right")
                                }
                            } header: {
                                Label("NOAA / Weather", systemImage: "cloud.bolt")
                            }
                        }

                        Section {
                            Picker(
                                "Transmission Hold",
                                selection: Binding(
                                    get: { viewModel.settings?.txHoldTime ?? 0 },
                                    set: { viewModel.updateTxHoldTime($0) }
                                )
                            ) {
                                ForEach(RadioPresentation.txHoldOptions) { option in
                                    Text(option.label).tag(option.value)
                                }
                            }

                            Picker(
                                "Time-Out Timer",
                                selection: Binding(
                                    get: { viewModel.settings?.txTimeLimit ?? 0 },
                                    set: { viewModel.updateTxTimeLimit($0) }
                                )
                            ) {
                                ForEach(RadioPresentation.txLimitOptions) { option in
                                    Text(option.label).tag(option.value)
                                }
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
                        } footer: {
                            Text("Transmission Hold keeps the transmitter active briefly after PTT release. Time-Out Timer limits continuous transmission.")
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
                                ForEach(RadioPresentation.screenTimeoutOptions) { option in
                                    Text(option.label).tag(option.value)
                                }
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

                            Picker(
                                selection: Binding(
                                    get: { viewModel.settings?.positioningSystem ?? 0 },
                                    set: { viewModel.updatePositioningSystem($0) }
                                )
                            ) {
                                Text("GPS").tag(0)
                                Text("GLONASS").tag(1)
                                Text("Beidou").tag(2)
                                Text("GPS + GLONASS").tag(3)
                            } label: {
                                Label("Positioning System", systemImage: "location")
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
                                Label("Keep Headset Connected", systemImage: "link")
                            }

                            Toggle(
                                isOn: Binding(
                                    get: { viewModel.settings?.disTone ?? false },
                                    set: { viewModel.updateDisTone($0) }
                                )
                            ) {
                                Label("Disable Key and Operation Tones", systemImage: "speaker.slash")
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

                        Section {
                            SupportDeveloperRow()
                        } header: {
                            Label("Support", systemImage: "heart")
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
    
    // The connection flow hydrates the controller before marking it connected.
    // Re-running hydration here races the background channel loader.
    private func hydrateRadio() async {
        await MainActor.run {
            isHydrating = true
        }
        await MainActor.run {
            isHydrating = false
            if radioManager.isConnected {
                viewModel.setRadioController(radioManager.radioController)
            }
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
