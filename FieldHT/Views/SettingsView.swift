import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var radioManager: RadioManager
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        Group {
            if !radioManager.isConnected {
                NotConnectedView()
            } else if viewModel.isLoading {
                ProgressView("Loading settings...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.settings != nil {
                settingsList
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView(
                    "Unable to Load Settings",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ContentUnavailableView("Settings Unavailable", systemImage: "gearshape")
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
            viewModel.setRadioController(isConnected ? radioManager.radioController : nil)
        }
        .onAppear {
            if radioManager.isConnected {
                viewModel.setRadioController(radioManager.radioController)
            }
        }
    }

    private var settingsList: some View {
        Form {
            Section {
                NavigationLink {
                    RadioSetupSettingsView(viewModel: viewModel)
                } label: {
                    Label("Radio Setup", systemImage: "gearshape.2")
                }

                NavigationLink {
                    AudioSettingsView(viewModel: viewModel)
                } label: {
                    Label("Audio", systemImage: "speaker.wave.2")
                }

                NavigationLink {
                    TransmissionSettingsView(viewModel: viewModel)
                } label: {
                    Label("Transmission", systemImage: "antenna.radiowaves.left.and.right")
                }

                NavigationLink {
                    PowerSettingsView(viewModel: viewModel)
                } label: {
                    Label("Power", systemImage: "bolt")
                }

                NavigationLink {
                    DisplaySettingsView(viewModel: viewModel)
                } label: {
                    Label("Display", systemImage: "display")
                }

                NavigationLink {
                    AdvancedSettingsView(viewModel: viewModel)
                } label: {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
            }

            Section {
                SupportDeveloperRow()
            } header: {
                Label("Support", systemImage: "heart")
            }
        }
        .disabled(viewModel.isSaving)
    }
}

private struct RadioSetupSettingsView: View {
    @EnvironmentObject private var radioManager: RadioManager
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                if let radioController = radioManager.radioController {
                    NavigationLink {
                        RadioControlCustomizationView()
                    } label: {
                        Label("Customize Radio Control", systemImage: "rectangle.3.group")
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
                }
            } header: {
                Text("Radio Setup")
            }

            Section("Positioning") {
                Picker("Positioning System", selection: settingBinding(\.positioningSystem, update: viewModel.updatePositioningSystem)) {
                    Text("GPS").tag(0)
                    Text("GLONASS").tag(1)
                    Text("Beidou").tag(2)
                    Text("GPS + GLONASS").tag(3)
                }
            }

            if radioManager.radioController?.deviceInfo.supportsNOAA == true {
                Section("Weather") {
                    Picker("Weather Mode", selection: settingBinding(\.wxMode, update: viewModel.updateWxMode)) {
                        Text("Off").tag(0)
                        Text("Monitor").tag(1)
                        Text("Alert").tag(2)
                    }
                    Picker("NOAA Channel", selection: settingBinding(\.noaaCh, update: viewModel.updateNoaaCh)) {
                        ForEach(0..<10) { channel in
                            Text("NOAA \(channel + 1)").tag(channel)
                        }
                    }
                }
            }
        }
        .navigationTitle("Radio Setup")
    }

    private func settingBinding(_ keyPath: KeyPath<Settings, Int>, update: @escaping (Int) -> Void) -> Binding<Int> {
        Binding(get: { viewModel.settings?[keyPath: keyPath] ?? 0 }, set: update)
    }
}

private struct AudioSettingsView: View {
    @EnvironmentObject private var radioManager: RadioManager
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Squelch", systemImage: "speaker.wave.2")
                        Spacer()
                        Text("\(viewModel.settings?.squelchLevel ?? 0)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
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

                Picker("Radio Mic Gain", selection: Binding(get: { viewModel.settings?.micGain ?? 0 }, set: viewModel.updateMicGain)) {
                    ForEach(RadioPresentation.micGainOptions) { option in
                        Text(option.label).tag(option.value)
                    }
                }

                Picker("Local Speaker", selection: Binding(get: { viewModel.settings?.localSpeaker ?? 0 }, set: viewModel.updateLocalSpeaker)) {
                    Text("Internal").tag(0)
                    Text("External").tag(1)
                    Text("Both").tag(2)
                }
            } header: {
                Text("Radio Audio")
            }

            if hasSpeakerMicControls {
                Section {
                    NavigationLink {
                        SpeakerMicView(viewModel: viewModel)
                            .environmentObject(radioManager)
                    } label: {
                        Label("Speaker Mic & BT Audio", systemImage: "mic.badge.plus")
                    }
                } footer: {
                    Text("Speaker-mic routing, battery, and Bluetooth audio controls are kept with the accessory.")
                }
            }
        }
        .navigationTitle("Audio")
    }

    private var hasSpeakerMicControls: Bool {
        radioManager.supportsSpeakerMicAccessory || radioManager.isBluetoothAudioConnected || radioManager.speakerMicController != nil || radioManager.lastSpeakerMicDeviceUUID != nil
    }
}

private struct TransmissionSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Picker("Transmission Hold", selection: Binding(get: { viewModel.settings?.txHoldTime ?? 0 }, set: viewModel.updateTxHoldTime)) {
                    ForEach(RadioPresentation.txHoldOptions) { option in
                        Text(option.label).tag(option.value)
                    }
                }

                Picker("Time-Out Timer", selection: Binding(get: { viewModel.settings?.txTimeLimit ?? 0 }, set: viewModel.updateTxTimeLimit)) {
                    ForEach(RadioPresentation.txLimitOptions) { option in
                        Text(option.label).tag(option.value)
                    }
                }

                Toggle("Tail Eliminator", isOn: Binding(get: { viewModel.settings?.tailElim ?? false }, set: viewModel.updateTailElim))
                Toggle("PTT Lock", isOn: Binding(get: { viewModel.settings?.pttLock ?? false }, set: viewModel.updatePttLock))
                Toggle("Dual Watch", isOn: Binding(get: { viewModel.isDualWatchOn }, set: viewModel.setDualWatch))
            } header: {
                Text("Transmission")
            } footer: {
                Text("Transmission Hold keeps the transmitter active briefly after PTT release. Time-Out Timer limits continuous transmission.")
            }

            Section {
                Toggle("Enable VOX", isOn: Binding(get: { viewModel.settings?.voxEnabled ?? false }, set: viewModel.updateVoxEnabled))

                Picker("Sensitivity", selection: Binding(get: { viewModel.settings?.voxLevel ?? 0 }, set: viewModel.updateVoxLevel)) {
                    ForEach(0...7, id: \.self) { value in
                        Text("Level \(value + 1)").tag(value)
                    }
                }
                .disabled(!(viewModel.settings?.voxEnabled ?? false))

                Picker("Delay", selection: Binding(get: { viewModel.settings?.voxDelay ?? 0 }, set: viewModel.updateVoxDelay)) {
                    ForEach(0...7, id: \.self) { value in
                        Text(value == 0 ? "Shortest" : "Level \(value + 1)").tag(value)
                    }
                }
                .disabled(!(viewModel.settings?.voxEnabled ?? false))

                Toggle("Disable Bluetooth Mic for VOX", isOn: Binding(get: { viewModel.settings?.disableBluetoothMic ?? false }, set: viewModel.updateDisableBluetoothMic))
                Toggle("Noise Suppression", isOn: Binding(get: { viewModel.settings?.noiseSuppressionEnabled ?? false }, set: viewModel.updateNoiseSuppressionEnabled))
            } header: {
                Text("VOX")
            } footer: {
                Text("VOX starts transmission when the selected microphone detects speech. Test sensitivity at low power before relying on it.")
            }
        }
        .navigationTitle("Transmission")
    }
}

private struct PowerSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Auto Power On", isOn: Binding(get: { viewModel.settings?.autoPowerOn ?? false }, set: viewModel.updateAutoPowerOn))

                Picker("Auto Power Off", selection: Binding(get: { viewModel.settings?.autoPowerOff ?? 0 }, set: viewModel.updateAutoPowerOff)) {
                    Text("Off").tag(0)
                    Text("Level 1 (Short)").tag(1)
                    Text("Level 2").tag(2)
                    Text("Level 3").tag(3)
                    Text("Level 4 (Medium)").tag(4)
                    Text("Level 5").tag(5)
                    Text("Level 6").tag(6)
                    Text("Level 7 (Long)").tag(7)
                }

                Toggle("Power Saving", isOn: Binding(get: { viewModel.settings?.powerSavingMode ?? false }, set: viewModel.updatePowerSavingMode))
            }
        }
        .navigationTitle("Power")
    }
}

private struct DisplaySettingsView: View {
    @AppStorage("FieldHT.appLanguage") private var appLanguage = "system"
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Radio Display") {
                Picker("Radio Screen Timeout", selection: Binding(get: { viewModel.settings?.screenTimeout ?? 0 }, set: viewModel.updateScreenTimeout)) {
                    ForEach(RadioPresentation.screenTimeoutOptions) { option in
                        Text(option.label).tag(option.value)
                    }
                }

                Toggle("Imperial Units", isOn: Binding(get: { viewModel.settings?.imperialUnit ?? false }, set: viewModel.updateImperialUnit))

                Picker("Radio Time Zone", selection: Binding(get: { signedTimeOffset }, set: { viewModel.updateTimeOffset($0 & 0x3F) })) {
                    ForEach(-12...14, id: \.self) { offset in
                        Text(timeZoneLabel(offset)).tag(offset)
                    }
                }
            }

            Section {
                Picker("Language", selection: $appLanguage) {
                    Text("System").tag("system")
                    Text("English").tag("en")
                }
            } header: {
                Text("App Appearance")
            }
        }
        .navigationTitle("Display")
    }

    private var signedTimeOffset: Int {
        let raw = viewModel.settings?.timeOffset ?? 0
        return raw >= 32 ? raw - 64 : raw
    }

    private func timeZoneLabel(_ offset: Int) -> String {
        offset == 0 ? "UTC" : "UTC\(offset > 0 ? "+" : "")\(offset)"
    }
}

private struct AdvancedSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Auto Relay", isOn: Binding(get: { viewModel.settings?.autoRelayEn ?? false }, set: viewModel.updateAutoRelayEn))
                Toggle("Keep Headset Connected", isOn: Binding(get: { viewModel.settings?.keepAghfpLink ?? false }, set: viewModel.updateKeepAghfpLink))
                Toggle("Disable Key and Operation Tones", isOn: Binding(get: { viewModel.settings?.disTone ?? false }, set: viewModel.updateDisTone))
                Toggle("Use Freq Range 2", isOn: Binding(get: { viewModel.settings?.useFreqRange2 ?? false }, set: viewModel.updateUseFreqRange2))
                Toggle("Leading Sync Bit", isOn: Binding(get: { viewModel.settings?.leadingSyncBitEn ?? false }, set: viewModel.updateLeadingSyncBitEn))
                Toggle("Pairing at Power On", isOn: Binding(get: { viewModel.settings?.pairingAtPowerOn ?? false }, set: viewModel.updatePairingAtPowerOn))
                Toggle("Disable Digital Mute", isOn: Binding(get: { viewModel.settings?.disDigitalMute ?? false }, set: viewModel.updateDisDigitalMute))
                Toggle("Signaling ECC", isOn: Binding(get: { viewModel.settings?.signalingEccEn ?? false }, set: viewModel.updateSignalingEccEn))
                Toggle("Channel Data Lock", isOn: Binding(get: { viewModel.settings?.chDataLock ?? false }, set: viewModel.updateChDataLock))
            } footer: {
                Text("Advanced options use radio firmware settings. Change them only when you know the behavior needed for your system.")
            }
        }
        .navigationTitle("Advanced")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(RadioManager())
    }
}
