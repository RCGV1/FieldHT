import SwiftUI
import CoreBluetooth

struct ConnectView: View {
    @EnvironmentObject var radioManager: RadioManager
    @StateObject private var scanner = BLEScanner()
    @State private var selectedDevice: DiscoveredDevice?

    private var connectedDeviceName: String? {
        if let selectedDevice {
            return selectedDevice.name
        }
        guard let uuid = radioManager.lastPairedDeviceUUID else { return nil }
        return scanner.knownDevice(for: uuid)?.name
    }

    private var isBusy: Bool {
        radioManager.isConnecting || radioManager.isAutoReconnecting
    }

    private var bluetoothStatusText: String {
        switch scanner.bluetoothState {
        case .poweredOn:
            return "On"
        case .poweredOff:
            return "Off"
        case .unsupported:
            return "Unsupported"
        case .unauthorized:
            return "Not Authorized"
        case .resetting:
            return "Resetting"
        case .unknown:
            return "Unknown"
        @unknown default:
            return "Unknown"
        }
    }

    private var scanStatusText: String {
        if radioManager.isConnected {
            return "Paused while connected"
        }
        return scanner.isScanning ? "Scanning" : "Stopped"
    }

    var body: some View {
        List {
            connectionStatusSection
            scannerStatusSection
            nearbyDevicesSection
            if !radioManager.isConnected {
                pairingInstructionsSection
            }
        }
        .navigationTitle("Connect Radio")
        .refreshable {
            if !radioManager.isConnected && !radioManager.isConnecting {
                scanner.stopScanning()
                try? await Task.sleep(nanoseconds: 500_000_000)
                scanner.startScanning()
            }
        }
        .task {
            updateScanningState()
        }
        .onChange(of: scanner.bluetoothState) {
            updateScanningState()
        }
        .onChange(of: radioManager.isConnected) {
            if radioManager.isConnected == true {
                if selectedDevice == nil,
                   let uuid = radioManager.lastPairedDeviceUUID {
                    selectedDevice = scanner.knownDevice(for: uuid)
                }
                updateScanningState()
            }
        }
    }

    @ViewBuilder
    private var connectionStatusSection: some View {
        Section("Connection") {
            if radioManager.isConnected {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(connectedDeviceName ?? "Connected Radio")
                            .font(.headline)
                        Text("Connected")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        radioManager.disconnect()
                        scanner.startScanning()
                        selectedDevice = nil
                    } label: {
                        Text("Disconnect")
                            .fontWeight(.semibold)
                    }
                }

                LabeledContent("Saved Device") {
                    Text(connectedDeviceName ?? "Unknown")
                }
            } else if isBusy {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(radioManager.isAutoReconnecting ? "Reconnecting…" : "Connecting…")
                        .foregroundStyle(.secondary)
                }
            } else if let error = radioManager.connectionError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            } else {
                Text("Select a radio below to connect.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var scannerStatusSection: some View {
        Section("Scanner") {
            LabeledContent("Bluetooth") {
                Text(bluetoothStatusText)
            }
            LabeledContent("Scan") {
                HStack(spacing: 8) {
                    if scanner.isScanning && !radioManager.isConnected {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(scanStatusText)
                }
            }
            if let uuid = radioManager.lastPairedDeviceUUID,
               let known = scanner.knownDevice(for: uuid) {
                LabeledContent("Last Paired") {
                    Text(known.name)
                }
            }
            if !radioManager.isConnected {
                Button {
                    scanner.stopScanning()
                    scanner.startScanning()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    @ViewBuilder
    private var nearbyDevicesSection: some View {
        Section {
            if scanner.bluetoothState != .poweredOn {
                ContentUnavailableView(
                    "Bluetooth Disabled",
                    systemImage: "bolt.horizontal.circle",
                    description: Text("Enable Bluetooth to discover and pair with a radio.")
                )
            } else if radioManager.isConnected {
                Text("Scanning is paused while connected.")
                    .foregroundStyle(.secondary)
            } else if scanner.discoveredDevices.isEmpty {
                ContentUnavailableView(
                    scanner.isScanning ? "Searching" : "No Radios Found",
                    systemImage: scanner.isScanning ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash",
                    description: Text("Pull to refresh or tap Rescan after enabling pairing mode on the radio.")
                )
            } else {
                ForEach(scanner.discoveredDevices) { device in
                    deviceRow(for: device)
                }
            }
        } header: {
            HStack {
                Text("Nearby Radios")
                Spacer()
                if scanner.isScanning && !radioManager.isConnected {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private var pairingInstructionsSection: some View {
        Section("Pairing Mode") {
            Text("On the radio, go to the main menu and toggle pairing.")
            Text("After that, tap Rescan or pull to refresh if it doesn’t show up right away.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func deviceRow(for device: DiscoveredDevice) -> some View {
        Button {
            connectToDevice(device)
            selectedDevice = device
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: device.isPaired ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(device.name)
                            .font(.body.weight(.semibold))
                        if device.isPaired {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                    }
                    Text("Signal \(device.rssi) dBm")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if selectedDevice?.id == device.id && radioManager.isConnected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.green)
                        .padding(.leading, 4)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if device.isPaired {
                Button(role: .destructive) {
                    scanner.clearLastPairedDevice()
                } label: {
                    Label("Unpair", systemImage: "trash")
                }
            }
        }
        .disabled(radioManager.isConnecting || radioManager.isConnected)
    }

    private func updateScanningState() {
        if !radioManager.isConnected,
           !radioManager.isConnecting,
           scanner.bluetoothState == .poweredOn,
           !scanner.isScanning {
            scanner.startScanning()
        }

        if (radioManager.isConnected || radioManager.isConnecting), scanner.isScanning {
            scanner.stopScanning()
        }
    }

    private func connectToDevice(_ device: DiscoveredDevice) {
        scanner.validateRadioService(device) { isRadio in
            guard isRadio else {
                print("Not a radio device")
                return
            }

            // Save as last paired device on successful validation
            scanner.saveLastPairedDevice(device)
            
            radioManager.connect(to: device.peripheral.identifier)
        }
    }
}

// MARK: - Preview
#Preview {
    ConnectView()
        .environmentObject(RadioManager())
}
