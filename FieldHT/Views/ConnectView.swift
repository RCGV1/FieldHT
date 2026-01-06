import SwiftUI
import CoreBluetooth

struct ConnectView: View {
    @EnvironmentObject var radioManager: RadioManager
    @StateObject private var scanner = BLEScanner()
    @State private var selectedDevice: DiscoveredDevice?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {

                // MARK: - Connection Status
                connectionStatusSection

                // MARK: - Device List
                deviceListSection
            }
            .navigationTitle("Connect to Radio")
        }
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
                updateScanningState()
            }
        }
    }

    // MARK: - Connection Status Section
    private var connectionStatusSection: some View {
        Group {
            if radioManager.isConnected {
                VStack(spacing: 12) {
                    if let device = selectedDevice {
                        Text(device.name)
                            .font(.title)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                        Text("Connected")
                            .font(.headline)
                    }
                   

                    Button {
                        radioManager.disconnect()
                        scanner.startScanning()
                        selectedDevice = nil
                    } label: {
                        Text("Disconnect")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(10)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.bottom, 20)

            }
        }
    }

    // MARK: - Device List Section
    private var deviceListSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Nearby Devices")
                    .font(.headline)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            if radioManager.isConnecting {
                HStack {
                    ProgressView()
                    Text("Connecting...")
                        .foregroundColor(.secondary)
                }
                .padding()
                .padding(.bottom, 20)

            } else if let error = radioManager.connectionError {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .padding()
                    .padding(.bottom, 20)
            } else if !scanner.statusMessage.isEmpty {
                Text(scanner.statusMessage)
                    .foregroundColor(.secondary)
                    .padding()
                    .padding(.bottom, 20)
            }
            if scanner.bluetoothState != .poweredOn {
                Text("Bluetooth is not available")
                    .foregroundColor(.red)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if scanner.discoveredDevices.isEmpty {
                ContentUnavailableView {
                    Label("No devices found", systemImage: "antenna.radiowaves.left.and.right.slash")
                } description: {
                    Text("Enter the Menu on your radio and enable pairing mode")
                }
            } else {
                List(scanner.discoveredDevices) { device in
                    Button {
                        connectToDevice(device)
                        selectedDevice = device
                    } label: {
                        HStack {
                            // Star icon for paired devices
                            if device.isPaired {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                    .font(.caption)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.name)
                                    .font(.headline)

                                Text(device.id.uuidString)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text("\(device.rssi) dBm")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                if selectedDevice?.id == device.id,
                                   radioManager.isConnected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .padding(.vertical, 4)
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
                .listStyle(.plain)
            }
        }
    }
    

    // MARK: - Scanning Logic
    private func updateScanningState() {
        // Start scanning by default when NOT connected
        if !radioManager.isConnected,
           scanner.bluetoothState == .poweredOn,
           !scanner.isScanning {
            scanner.startScanning()
        }

        // Stop scanning once connected
        if radioManager.isConnected, scanner.isScanning {
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
