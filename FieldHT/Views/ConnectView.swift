//
//  ConnectView.swift
//  FieldHT
//
//  Created by Benjamin Faershtein on 12/13/25.
//

import SwiftUI
import CoreBluetooth

struct ConnectView: View {
    @EnvironmentObject var radioManager: RadioManager
    @StateObject private var scanner = BLEScanner()
    @State private var selectedDevice: DiscoveredDevice?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {

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
            updateScanningState()
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

            } else if radioManager.isConnecting {
                HStack {
                    ProgressView()
                    Text("Connecting...")
                        .foregroundColor(.secondary)
                }
                .padding()

            } else if let error = radioManager.connectionError {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .padding()
            }
        }
    }

    // MARK: - Device List Section
    private var deviceListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Nearby Devices")
                    .font(.headline)

                Spacer()

                Button {
                    toggleScan()
                } label: {
                    Text(scanner.isScanning ? "Stop Scan" : "Start Scan")
                        .font(.subheadline)
                }
                .disabled(radioManager.isConnected)
            }
            .padding(.horizontal)

            if scanner.bluetoothState != .poweredOn {
                Text("Bluetooth is not available")
                    .foregroundColor(.red)
                    .padding()

            } else if scanner.discoveredDevices.isEmpty {
                Text(scanner.isScanning
                     ? "Scanning for radio devices..."
                     : "No devices found")
                    .foregroundColor(.secondary)
                    .padding()

            } else {
                List(scanner.discoveredDevices) { device in
                    Button {
                        connectToDevice(device)
                        selectedDevice = device
                    } label: {
                        HStack {
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
                    .disabled(radioManager.isConnecting || radioManager.isConnected)
                }
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

    private func toggleScan() {
        if scanner.isScanning {
            scanner.stopScanning()
        } else {
            scanner.startScanning()
        }
    }

    // MARK: - Connection Logic
    private func connectToDevice(_ device: DiscoveredDevice) {
        scanner.validateRadioService(device) { isRadio in
            guard isRadio else {
                print("Not a radio device")
                return
            }

            radioManager.connect(to: device.peripheral.identifier)
        }
    }
}

// MARK: - Preview
#Preview {
    ConnectView()
        .environmentObject(RadioManager())
}
