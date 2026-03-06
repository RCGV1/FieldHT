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

    var body: some View {
        NavigationStack {
            List {
                connectionStatusSection
                nearbyDevicesSection
            }
            .navigationTitle("Connect Radio")
            // Start scanning automatically on open
            .task {
                updateScanningState()
            }
            // React to Bluetooth power changes
            .onChange(of: scanner.bluetoothState) {
                updateScanningState()
            }
            // React to connect / disconnect
            .onChange(of: radioManager.isConnected) {
                if radioManager.isConnected == true {
                    if selectedDevice == nil,
                       let uuid = radioManager.lastPairedDeviceUUID {
                        selectedDevice = scanner.knownDevice(for: uuid)
                    }
                    updateScanningState()
                }
            }
            // Add a refresh action to manually trigger a scan if not connected
            .refreshable {
                if !radioManager.isConnected && !radioManager.isConnecting {
                    scanner.stopScanning()
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    scanner.startScanning()
                }
            }
        }
    }

    // MARK: - Connection Status Section
    @ViewBuilder
    private var connectionStatusSection: some View {
        if radioManager.isConnected {
            Section("Current Connection") {
                HStack {
                    Image(systemName: "radio.fill")
                        .foregroundColor(.green)
                        .imageScale(.large)
                        .padding(.trailing, 8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connectedDeviceName ?? "Connected Radio")
                            .font(.headline)
                        Text("Connected")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(role: .destructive) {
                        radioManager.disconnect()
                        scanner.startScanning()
                        selectedDevice = nil
                    } label: {
                        Text("Disconnect")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            }
        } else if radioManager.isConnecting || radioManager.isAutoReconnecting {
            Section("Current Connection") {
                HStack {
                    ProgressView()
                        .padding(.trailing, 12)
                    Text(radioManager.isAutoReconnecting ? "Reconnecting..." : "Connecting...")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        } else if let error = radioManager.connectionError {
            Section("Connection Error") {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - Device List Section
    @ViewBuilder
    private var nearbyDevicesSection: some View {
        Section {
            if scanner.bluetoothState != .poweredOn {
                ContentUnavailableView(
                    "Bluetooth Disabled",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Please enable Bluetooth to connect to a radio.")
                )
            } else if radioManager.isConnected {
                HStack {
                    Spacer()
                    Text("Scanning paused while connected")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    Spacer()
                }
            } else if scanner.discoveredDevices.isEmpty {
                ContentUnavailableView(
                    scanner.isScanning ? "Searching" : "No Radios Found",
                    systemImage: scanner.isScanning ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash",
                    description: Text(scanner.isScanning ? "Looking for nearby radios..." : "Make sure your radio is in pairing mode.")
                )
            } else {
                ForEach(scanner.discoveredDevices) { device in
                    deviceRow(for: device)
                }
            }
        } header: {
            HStack {
                Text("Nearby Devices")
                Spacer()
                if scanner.isScanning && !radioManager.isConnected {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }
    
    // MARK: - Subviews
    private func deviceRow(for device: DiscoveredDevice) -> some View {
        Button {
            connectToDevice(device)
            selectedDevice = device
        } label: {
            HStack {
                if device.isPaired {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                }
                
                Text(device.name)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                Text("\(device.rssi) dBm")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if selectedDevice?.id == device.id && radioManager.isConnected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.green)
                        .padding(.leading, 4)
                }
            }
        }
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

    // MARK: - Scanning Logic
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

    // MARK: - Connection Logic
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
