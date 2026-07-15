//
//  BeaconSettingsView.swift
//  FieldHT
//
//  Created by FieldHT on today.
//

import SwiftUI

struct BeaconSettingsView: View {
    @EnvironmentObject var radioManager: RadioManager

    @State private var isLoading = false
    @State private var isSaving = false
    @State private var settings: BeaconSettings?
    @State private var loadError: String?
    
    // Binding states
    @State private var packetFormat: PacketFormat = .bss
    @State private var aprsCallsign: String = ""
    @State private var aprsSSID: Int = 0
    @State private var aprsSymbol: String = ""
    @State private var beaconMessage: String = ""
    
    @State private var shouldShareLocation: Bool = false
    @State private var pttReleaseSendLocation: Bool = false
    @State private var pttReleaseSendIDInfo: Bool = false
    @State private var pttReleaseSendBSSUserID: Bool = false
    @State private var sendPwrVoltage: Bool = false
    @State private var allowPositionCheck: Bool = false
    @State private var micEEnabled: Bool = false
    @State private var sendIDByAPRS: Bool = false
    
    @State private var locationShareInterval: Int = 0
    @State private var timeToLive: Int = 0
    @State private var maxFwdTimes: Int = 0
    @State private var smartBeaconEnabled: Bool = false
    @State private var smartBeaconMinimumInterval: Int = 0
    @State private var smartBeaconMaximumInterval: Int = 0
    @State private var supportsSmartBeaconIntervals = false
    
    var body: some View {
        Form {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading Settings...")
                        Spacer()
                    }
                }
            } else if let loadError = loadError {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    Text("Failed to Load")
                        .font(.title2).fontWeight(.semibold)
                    Text(loadError)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") { loadSettings() }
                        .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if settings != nil {
                Section(header: Text("Packet Format")) {
                    Picker("Format", selection: $packetFormat) {
                        ForEach(PacketFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section(header: Text("APRS Identity"), footer: Text("Enter your amateur radio callsign, optional SSID, and a two-character APRS symbol.")) {
                    TextField("Callsign", text: $aprsCallsign)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                    
                    HStack {
                        Text("SSID")
                        Spacer()
                        TextField("0-15", value: $aprsSSID, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    APRSSymbolRow(selectedCode: aprsSymbol) { sym in
                        aprsSymbol = sym.code
                    }

                    if packetFormat == .aprs {
                        Toggle("Enable Mic-E", isOn: $micEEnabled)
                        Toggle("Send ID by APRS", isOn: $sendIDByAPRS)
                    }
                }
                
                Section(header: Text("Location Sharing"), footer: Text("The radio stores the sharing interval in 10-second steps.")) {
                    TextField("Beacon Message", text: $beaconMessage)
                    
                    HStack {
                        Text("Sharing Interval (s)")
                        Spacer()
                        TextField("Seconds", value: $locationShareInterval, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                if supportsSmartBeaconIntervals {
                    Section(header: Text("Smart Beaconing"), footer: Text("The radio adjusts beacon timing based on movement. Minimum and maximum intervals are in minutes.")) {
                        Toggle("Enable Smart Beacon", isOn: $smartBeaconEnabled)

                        Picker("Minimum Interval", selection: $smartBeaconMinimumInterval) {
                            ForEach(0...15, id: \.self) { value in
                                Text(value == 0 ? "Use share interval" : "\(value) minutes").tag(value)
                            }
                        }

                        Picker("Maximum Interval", selection: $smartBeaconMaximumInterval) {
                            ForEach(0...30, id: \.self) { value in
                                Text(value == 0 ? "Use radio default" : "\(value) minutes").tag(value)
                            }
                        }
                    }
                }
                
                Section(header: Text("PTT Release")) {
                    Toggle("Send Location on PTT Release", isOn: $pttReleaseSendLocation)
                    Toggle("Send ID Info on PTT Release", isOn: $pttReleaseSendIDInfo)
                    Toggle("Send BSS ID on PTT Release", isOn: $pttReleaseSendBSSUserID)
                }
                
                Section(header: Text("Location and Station Data")) {
                    Toggle("Should Share Location", isOn: $shouldShareLocation)
                    Toggle("Allow Position Check", isOn: $allowPositionCheck)
                    Toggle("Send Power/Voltage", isOn: $sendPwrVoltage)
                    
                }

                Section(header: Text("Digipeater"), footer: Text("Set both Time to Live and Maximum Forwards above zero before relying on packet forwarding.")) {
                    HStack {
                        Text("Time to Live")
                        Spacer()
                        TextField("TTL", value: $timeToLive, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Maximum Forwards")
                        Spacer()
                        TextField("Forwards", value: $maxFwdTimes, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
            } else {
                ContentUnavailableView {
                    Label("Not Connected", systemImage: "antenna.radiowaves.left.and.right.slash")
                } description: {
                    Text("Connect to a radio device to load beacon settings")
                }
            }
        }
        .navigationTitle("APRS / Packet Beaconing")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSaving {
                    ProgressView()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { saveSettings() }
                    .disabled(isSaving || isLoading || settings == nil)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    loadSettings()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .disabled(isLoading || isSaving)
            }
        }
        .onAppear {
            loadSettings()
        }
    }
    
    private func loadSettings() {
        guard radioManager.isConnected else { return }
        isLoading = true
        loadError = nil

        Task {
            do {
                if radioManager.radioController?.state == nil {
                    try? await radioManager.radioController?.hydrate()
                }
                let currentSettings = try await radioManager.getBeaconSettings()

                self.settings = currentSettings
                self.packetFormat = currentSettings.packetFormat
                self.aprsCallsign = currentSettings.aprsCallsign.trimmingCharacters(in: .whitespacesAndNewlines)
                self.aprsSSID = currentSettings.aprsSSID
                self.aprsSymbol = currentSettings.aprsSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
                self.beaconMessage = currentSettings.beaconMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                self.shouldShareLocation = currentSettings.shouldShareLocation
                self.pttReleaseSendLocation = currentSettings.pttReleaseSendLocation
                self.pttReleaseSendIDInfo = currentSettings.pttReleaseSendIDInfo
                self.pttReleaseSendBSSUserID = currentSettings.pttReleaseSendBSSUserID
                self.sendPwrVoltage = currentSettings.sendPwrVoltage
                self.allowPositionCheck = currentSettings.allowPositionCheck
                self.micEEnabled = currentSettings.micEEnabled
                self.sendIDByAPRS = currentSettings.sendIDByAPRS
                self.locationShareInterval = currentSettings.locationShareInterval
                self.timeToLive = currentSettings.timeToLive
                self.maxFwdTimes = currentSettings.maxFwdTimes
                self.smartBeaconEnabled = currentSettings.smartBeaconEnabled
                if let minimum = currentSettings.smartBeaconMinimumInterval,
                   let maximum = currentSettings.smartBeaconMaximumInterval {
                    self.smartBeaconMinimumInterval = minimum
                    self.smartBeaconMaximumInterval = maximum
                    self.supportsSmartBeaconIntervals = true
                } else {
                    self.supportsSmartBeaconIntervals = false
                }
                self.isLoading = false
            } catch {
                print("Error loading beacon settings: \(error)")
                self.loadError = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    private func saveSettings() {
        guard var updatedSettings = settings else { return }
        isSaving = true
        
        updatedSettings.packetFormat = packetFormat
        updatedSettings.aprsCallsign = aprsCallsign
        updatedSettings.aprsSSID = aprsSSID
        updatedSettings.aprsSymbol = aprsSymbol
        updatedSettings.beaconMessage = beaconMessage
        
        updatedSettings.shouldShareLocation = shouldShareLocation
        updatedSettings.pttReleaseSendLocation = pttReleaseSendLocation
        updatedSettings.pttReleaseSendIDInfo = pttReleaseSendIDInfo
        updatedSettings.pttReleaseSendBSSUserID = pttReleaseSendBSSUserID
        updatedSettings.sendPwrVoltage = sendPwrVoltage
        updatedSettings.allowPositionCheck = allowPositionCheck
        updatedSettings.micEEnabled = micEEnabled
        updatedSettings.sendIDByAPRS = sendIDByAPRS
        
        updatedSettings.locationShareInterval = locationShareInterval
        updatedSettings.timeToLive = timeToLive
        updatedSettings.maxFwdTimes = maxFwdTimes
        if supportsSmartBeaconIntervals {
            updatedSettings.smartBeaconEnabled = smartBeaconEnabled
            updatedSettings.smartBeaconMinimumInterval = smartBeaconMinimumInterval
            updatedSettings.smartBeaconMaximumInterval = smartBeaconMaximumInterval
        }
        
        Task {
            do {
                try await radioManager.setBeaconSettings(updatedSettings)
                self.settings = updatedSettings
                isSaving = false
            } catch {
                print("Error saving beacon settings: \(error)")
                isSaving = false
            }
        }
    }
}

#Preview {
    NavigationView {
        BeaconSettingsView()
            .environmentObject(RadioManager())
    }
}
