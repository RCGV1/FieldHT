import SwiftUI
import CoreBluetooth

struct SpeakerMicView: View {
    @EnvironmentObject var radioManager: RadioManager
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var scanner = BLEScanner()
    @State private var hasAttemptedAutoReconnect = false

    private var accessoryController: SpeakerMicController? {
        radioManager.speakerMicController
    }

    private var hasDirectAccessoryLink: Bool {
        accessoryController?.isConnected == true
    }

    private var connectedBS22: SpeakerMicController? {
        guard let accessoryController, accessoryController.isConnected, accessoryController.isBS22 else { return nil }
        return accessoryController
    }

    private var speakerMicName: String {
        RadioPresentation.speakerMicName(
            model: accessoryController?.productSummary,
            isBS22: accessoryController?.isBS22 == true
        )
    }

    private var isSpeakerMicAvailableThroughRadio: Bool {
        radioManager.isSpeakerMicConnected
    }

    private var savedAccessory: DiscoveredDevice? {
        guard let uuid = radioManager.lastSpeakerMicDeviceUUID else { return nil }
        return scanner.knownDevice(for: uuid)
    }

    private var nearbyAccessoryCandidates: [DiscoveredDevice] {
        scanner.discoveredDevices.filter { device in
            if device.id == radioManager.lastPairedDeviceUUID {
                return false
            }
            return true
        }
    }

    private var isScanningForAccessories: Bool {
        scanner.isScanning && accessoryController?.isConnected != true
    }

    private var isSavedAccessoryAvailable: Bool {
        radioManager.lastSpeakerMicDeviceUUID != nil
    }

    private var speakerMicBatteryPercent: Int? {
        if let accessoryController, (1...100).contains(accessoryController.batteryPercent) {
            return accessoryController.batteryPercent
        }
        if (1...100).contains(radioManager.hmBatteryLevel) {
            return radioManager.hmBatteryLevel
        }
        return nil
    }

    private var batteryCaption: String {
        if hasDirectAccessoryLink {
            return "Read directly from the speaker mic."
        }
        return "Read through the radio link."
    }

    private var hmSpeakerBinding: Binding<Int> {
        Binding(
            get: { viewModel.settings?.hmSpeaker ?? 0 },
            set: { newValue in
                guard viewModel.settings?.hmSpeaker != newValue else { return }
                viewModel.updateHmSpeaker(newValue)
            }
        )
    }

    private var btMicGainBinding: Binding<Int> {
        Binding(
            get: { viewModel.settings?.btMicGain ?? 0 },
            set: { newValue in
                guard viewModel.settings?.btMicGain != newValue else { return }
                viewModel.updateBtMicGain(newValue)
            }
        )
    }

    private var aghfpCallModeBinding: Binding<Int> {
        Binding(
            get: { viewModel.settings?.aghfpCallMode ?? 0 },
            set: { newValue in
                guard viewModel.settings?.aghfpCallMode != newValue else { return }
                viewModel.updateAghfpCallMode(newValue)
            }
        )
    }

    var body: some View {
        Group {
            if !radioManager.isConnected {
                NotConnectedView()
            } else if viewModel.isLoading {
                ProgressView("Loading accessory settings...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.settings != nil {
                Form {
                    Section {
                        statusSummary

                        if let battery = speakerMicBatteryPercent {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Battery")
                                    Spacer()
                                    Text("\(battery)%")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                ProgressView(value: Double(battery), total: 100)
                                    .tint(batteryTint(for: battery))
                                Text(batteryCaption)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }

                        if let accessoryController, accessoryController.isConnected {
                            LabeledContent("Accessory Model") {
                                Text(accessoryController.productSummary)
                                    .foregroundStyle(.secondary)
                            }

                            if let firmware = accessoryController.firmwareVersionText {
                                LabeledContent("Accessory Firmware") {
                                    Text(firmware)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Button("Disconnect Speaker Mic", role: .destructive) {
                                radioManager.disconnectSpeakerMic()
                            }
                        } else if radioManager.isSpeakerMicConnecting {
                            ProgressView("Connecting to speaker mic...")
                        } else if let savedAccessory {
                            Button {
                                connectAccessory(savedAccessory)
                            } label: {
                                Label("Reconnect Speaker Mic", systemImage: "link.badge.plus")
                            }
                        }

                        if let error = radioManager.speakerMicConnectionError, !error.isEmpty {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    } header: {
                        Text("Speaker Mic")
                    }

                    if accessoryController?.isConnected != true {
                        Section {
                            directConnectAction

                            if scanner.bluetoothState != .poweredOn {
                                hintRow(title: "Bluetooth is off", detail: "Turn it on to discover the speaker mic.")
                            } else if nearbyAccessoryCandidates.isEmpty {
                                hintRow(
                                    title: isScanningForAccessories ? "Looking for speaker mics..." : "No speaker mic found",
                                    detail: isSavedAccessoryAvailable
                                        ? "This screen will try the last speaker mic automatically. Scan if you want to pick a different one."
                                        : "The radio can still use the speaker mic on its own. Connect directly only when you want battery, firmware, or button setup."
                                )
                            } else {
                                ForEach(nearbyAccessoryCandidates) { device in
                                    Button {
                                        connectAccessory(device)
                                    } label: {
                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(device.name)
                                                    .foregroundStyle(.primary)
                                                Text(signalLabel(for: device.rssi))
                                                    .font(.footnote)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "link")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("Direct Speaker Mic Connection")
                        } footer: {
                            Text("FieldHT currently supports direct button setup for the BS-22 only. It will try to reconnect the last speaker mic automatically when this screen opens.")
                        }
                    }

                    if let accessoryController = connectedBS22 {
                        Section {
                            NavigationLink {
                                SpeakerMicPFSettingsView(controller: accessoryController)
                            } label: {
                                Label("Configure BS-22 Buttons", systemImage: "button.programmable")
                            }
                        } header: {
                            Text("Button Setup")
                        } footer: {
                            Text("Button mappings come from the BS-22 speaker mic itself, not the radio.")
                        }
                    }

                    Section {
                        Picker(selection: hmSpeakerBinding) {
                            Text("Automatic").tag(0)
                            Text("On").tag(1)
                            Text("Off").tag(2)
                            Text("Squelch").tag(3)
                        } label: {
                            Label("Speaker-Mic Audio", systemImage: "speaker.wave.3")
                        }

                        if radioManager.isBluetoothAudioConnected {
                            Picker(selection: btMicGainBinding) {
                                ForEach(RadioPresentation.micGainOptions) { option in
                                    Text(option.label).tag(option.value)
                                }
                            } label: {
                                Label("BT Mic Gain", systemImage: "mic.and.signal.meter")
                            }

                            Picker(selection: aghfpCallModeBinding) {
                                Text("Voice").tag(0)
                                Text("Phone").tag(1)
                            } label: {
                                Label("Headset Mode", systemImage: "phone")
                            }
                        }
                    } header: {
                        Text("Audio Routing")
                    } footer: {
                        Text("Automatic preserves the radio's normal routing. Headset Mode selects Voice or Phone behavior for supported Bluetooth headsets.")
                    }

                }
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 52))
                        .foregroundColor(.red)
                    Text("Accessory Settings Unavailable")
                        .font(.title3.weight(.semibold))
                    Text(error)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("No Accessory Data", systemImage: "mic.slash")
                } description: {
                    Text("Connect to the radio to see speaker-mic and Bluetooth audio controls.")
                }
            }
        }
        .navigationTitle("Speaker Mic")
        .task {
            autoReconnectSavedSpeakerMicIfNeeded()
        }
        .onChange(of: radioManager.speakerMicController?.isConnected == true) {
            updateScanningState()
        }
        .onChange(of: scanner.bluetoothState) {
            updateScanningState()
            autoReconnectSavedSpeakerMicIfNeeded()
        }
        .onChange(of: radioManager.lastSpeakerMicDeviceUUID) {
            hasAttemptedAutoReconnect = false
            autoReconnectSavedSpeakerMicIfNeeded()
        }
        .onDisappear {
            hasAttemptedAutoReconnect = false
        }
    }

    private func connectAccessory(_ device: DiscoveredDevice) {
        radioManager.connectSpeakerMic(to: device.peripheral.identifier)
    }

    private func autoReconnectSavedSpeakerMicIfNeeded() {
        guard !hasAttemptedAutoReconnect else { return }
        guard radioManager.isConnected else { return }
        guard accessoryController?.isConnected != true else { return }
        guard !radioManager.isSpeakerMicConnecting else { return }
        guard let lastUUID = radioManager.lastSpeakerMicDeviceUUID else { return }

        // Wait until Bluetooth is in a real state before trying; if it is still
        // coming up, onChange will re-run this once ready.
        guard scanner.bluetoothState == .poweredOn || scanner.bluetoothState == .unknown else { return }

        hasAttemptedAutoReconnect = true
        radioManager.connectSpeakerMic(to: lastUUID)
    }

    private func updateScanningState() {
        if (accessoryController?.isConnected == true || radioManager.isSpeakerMicConnecting), scanner.isScanning {
            scanner.stopScanning()
        }
    }

    private var statusText: String {
        if hasDirectAccessoryLink {
            return "\(speakerMicName) connected"
        }
        if isSpeakerMicAvailableThroughRadio {
            return "Detected through radio"
        }
        return "Not detected"
    }

    @ViewBuilder
    private var statusSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: hasDirectAccessoryLink ? "checkmark.circle.fill" : "mic")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(hasDirectAccessoryLink ? .green : .blue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.headline)
                    Text(hasDirectAccessoryLink ? "Direct link active for battery, firmware, and button setup." : "The radio can still use the mic even without the direct setup link.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var directConnectAction: some View {
        if radioManager.isSpeakerMicConnecting {
            HStack(spacing: 12) {
                ProgressView()
                Text("Connecting to speaker mic...")
                    .foregroundStyle(.secondary)
            }
        } else if let savedAccessory {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    connectAccessory(savedAccessory)
                } label: {
                    Label("Reconnect Last Speaker Mic", systemImage: "link.badge.plus")
                }

                Button {
                    if scanner.isScanning {
                        scanner.stopScanning()
                    } else {
                        scanner.startScanning(mode: .allDevices)
                    }
                } label: {
                    Label(
                    isScanningForAccessories ? "Stop Scan" : "Find Another Speaker Mic",
                        systemImage: isScanningForAccessories ? "stop.circle" : "dot.radiowaves.left.and.right"
                    )
                }
                .buttonStyle(.bordered)
            }
        } else {
            Button {
                if scanner.isScanning {
                    scanner.stopScanning()
                } else {
                    scanner.startScanning(mode: .allDevices)
                }
            } label: {
                Label(
                    isScanningForAccessories ? "Stop Scan" : "Find Speaker Mic",
                    systemImage: isScanningForAccessories ? "stop.circle" : "dot.radiowaves.left.and.right"
                )
            }
        }
    }

    @ViewBuilder
    private func hintRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func signalLabel(for rssi: Int) -> String {
        if rssi >= -65 { return "Strong signal" }
        if rssi >= -78 { return "Nearby" }
        return "Weak signal"
    }

    private func batteryTint(for percent: Int) -> Color {
        switch percent {
        case 0..<20: return .red
        case 20..<45: return .orange
        default: return .green
        }
    }
}
