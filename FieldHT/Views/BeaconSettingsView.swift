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
    @State private var isDigitalModeEnabled = true
    @State private var didChangeDigitalMode = false
    @State private var packetFormat: PacketFormat = .bss
    @State private var beaconTransmitChannel: Int?
    @State private var kissTNCEnabled = false
    @State private var aprsCallsign: String = ""
    @State private var aprsSSID: Int = 0
    @State private var aprsSymbol: String = ""
    @State private var beaconMessage: String = ""
    @State private var aprsPath: String = ""
    @State private var supportsAPRSPath = false
    
    @State private var shouldShareLocation: Bool = false
    @State private var pttReleaseSendLocation: Bool = false
    @State private var pttReleaseSendIDInfo: Bool = false
    @State private var pttReleaseSendBSSUserID: Bool = false
    @State private var sendPwrVoltage: Bool = false
    @State private var allowPositionCheck: Bool = false
    @State private var micEEnabled: Bool = false
    @State private var sendIDByAPRS: Bool = false
    
    @State private var locationShareInterval: Int = BeaconTimingPolicy.defaultInterval
    @State private var timeToLive: Int = 0
    @State private var maxFwdTimes: Int = 0
    @State private var smartBeaconEnabled: Bool = false
    @State private var smartBeaconMaximumInterval: Int = 0
    @State private var supportsSmartBeaconIntervals = false

    private var firmwareVersion: Int {
        radioManager.radioController?.deviceInfo.firmwareVersion ?? 0
    }

    private var supportsMicE: Bool {
        firmwareVersion >= 135
    }

    private var supportsSendIDByAPRS: Bool {
        firmwareVersion >= 138
    }

    private var supportsExtendedSmartBeaconing: Bool {
        firmwareVersion >= 146
    }

    private var memoryChannels: [Channel] {
        radioManager.channels
            .filter { $0.channelID < 250 && $0.rxFreq > 0 }
            .sorted { $0.channelID < $1.channelID }
    }
    
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
                Section("Digital Mode") {
                    Toggle("Enable BSS / APRS", isOn: Binding(
                        get: { isDigitalModeEnabled },
                        set: {
                            isDigitalModeEnabled = $0
                            didChangeDigitalMode = true
                        }
                    ))

                    Picker("Packet Format", selection: $packetFormat) {
                        ForEach(PacketFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!isDigitalModeEnabled)

                    Picker("Transmit Channel", selection: $beaconTransmitChannel) {
                        Text("Current Channel").tag(nil as Int?)
                        ForEach(memoryChannels, id: \.channelID) { channel in
                            Text(RadioPresentation.channelMenuLabel(channelID: channel.channelID, name: channel.name))
                                .tag(Optional(channel.channelID))
                        }
                    }
                    .disabled(!isDigitalModeEnabled)

                    Toggle("KISS TNC", isOn: $kissTNCEnabled)
                        .disabled(!isDigitalModeEnabled)
                }
                
                if packetFormat == .aprs {
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

                    if supportsMicE {
                        Toggle("Enable Mic-E", isOn: $micEEnabled)
                    }
                    if supportsSendIDByAPRS {
                        Toggle("Send ID by APRS", isOn: $sendIDByAPRS)
                    }
                }
                }

                if packetFormat == .aprs, supportsAPRSPath {
                    Section(header: Text("APRS Path"), footer: Text("The path controls which digipeaters relay an APRS packet. FieldHT keeps up to eight path entries, matching the radio programmer.")) {
                        TextField("WIDE1-1,WIDE2-1", text: $aprsPath)
                            .textInputAutocapitalization(.characters)
                            .disableAutocorrection(true)

                        Menu("Use a Common Path") {
                            ForEach(commonAPRSPaths, id: \.self) { path in
                                Button(path) {
                                    aprsPath = path
                                }
                            }
                        }
                    }
                }

                if packetFormat == .aprs {
                    Section("APRS Internet") {
                        NavigationLink {
                            APRSIGateSettingsView()
                                .environmentObject(radioManager)
                        } label: {
                            Label("Internet Gateway", systemImage: "network")
                        }
                    }
                }
                
                Section(header: Text("Location Beaconing"), footer: Text(locationBeaconingFooter)) {
                    Toggle("Share Location", isOn: $shouldShareLocation)

                    TextField("Beacon Message", text: $beaconMessage)
                    
                    Picker(smartBeaconEnabled ? "Minimum Interval" : "Beacon Interval", selection: $locationShareInterval) {
                        ForEach(BeaconTimingPolicy.baseIntervals, id: \.self) { interval in
                            Text(BeaconTimingPolicy.label(for: interval)).tag(interval)
                        }
                    }
                    .disabled(!shouldShareLocation && !smartBeaconEnabled)

                    Toggle("Allow Position Check", isOn: $allowPositionCheck)
                    Toggle("Send Power / Voltage", isOn: $sendPwrVoltage)
                }

                if packetFormat == .aprs {
                    Section(header: Text("Smart Beaconing"), footer: Text(smartBeaconFooter)) {
                        Toggle("Enable Smart Beacon", isOn: Binding(
                            get: { smartBeaconEnabled },
                            set: { enabled in
                                smartBeaconEnabled = enabled
                                if enabled {
                                    shouldShareLocation = true
                                    locationShareInterval = BeaconTimingPolicy.normalizedBaseInterval(
                                        locationShareInterval,
                                        isBeaconingEnabled: true
                                    )
                                }
                            }
                        ))

                        if supportsSmartBeaconIntervals {
                            Picker("Maximum Interval", selection: $smartBeaconMaximumInterval) {
                                ForEach(BeaconTimingPolicy.smartBeaconMaximumIntervals, id: \.self) { value in
                                    let unit = value == 1 ? "minute" : "minutes"
                                    Text("\(value) \(unit)").tag(value)
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text("PTT Release")) {
                    Toggle("Send Location on PTT Release", isOn: $pttReleaseSendLocation)
                    Toggle("Send ID Info on PTT Release", isOn: $pttReleaseSendIDInfo)
                    Toggle("Send BSS ID on PTT Release", isOn: $pttReleaseSendBSSUserID)
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
        .scrollDismissesKeyboard(.interactively)
        .fieldHTKeyboardDismissal()
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
                if let radioSettings = radioManager.radioController?.state?.settings {
                    self.beaconTransmitChannel = radioSettings.autoShareLocCh
                    self.kissTNCEnabled = radioSettings.kissEnabled
                }
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
                self.locationShareInterval = BeaconTimingPolicy.normalizedBaseInterval(
                    currentSettings.locationShareInterval,
                    isBeaconingEnabled: currentSettings.shouldShareLocation || currentSettings.smartBeaconEnabled
                )
                self.timeToLive = currentSettings.timeToLive
                self.maxFwdTimes = currentSettings.maxFwdTimes
                self.smartBeaconEnabled = currentSettings.smartBeaconEnabled
                if supportsExtendedSmartBeaconing,
                   let maximum = currentSettings.smartBeaconMaximumInterval {
                    self.smartBeaconMaximumInterval = BeaconTimingPolicy.normalizedMaximumInterval(maximum)
                    self.supportsSmartBeaconIntervals = true
                } else {
                    self.supportsSmartBeaconIntervals = false
                }
                guard firmwareVersion >= 86 else {
                    self.supportsAPRSPath = false
                    self.isLoading = false
                    return
                }
                do {
                    self.aprsPath = try await radioManager.getAPRSPath()
                    self.supportsAPRSPath = true
                } catch {
                    self.supportsAPRSPath = false
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
        
        let beaconingEnabled = shouldShareLocation || smartBeaconEnabled
        updatedSettings.shouldShareLocation = beaconingEnabled
        updatedSettings.pttReleaseSendLocation = pttReleaseSendLocation
        updatedSettings.pttReleaseSendIDInfo = pttReleaseSendIDInfo
        updatedSettings.pttReleaseSendBSSUserID = pttReleaseSendBSSUserID
        updatedSettings.sendPwrVoltage = sendPwrVoltage
        updatedSettings.allowPositionCheck = allowPositionCheck
        updatedSettings.micEEnabled = micEEnabled
        updatedSettings.sendIDByAPRS = sendIDByAPRS
        
        updatedSettings.locationShareInterval = BeaconTimingPolicy.normalizedBaseInterval(
            locationShareInterval,
            isBeaconingEnabled: beaconingEnabled
        )
        updatedSettings.timeToLive = timeToLive
        updatedSettings.maxFwdTimes = maxFwdTimes
        updatedSettings.smartBeaconEnabled = smartBeaconEnabled
        if supportsSmartBeaconIntervals {
            updatedSettings.smartBeaconMaximumInterval = BeaconTimingPolicy.normalizedMaximumInterval(smartBeaconMaximumInterval)
        }
        
        Task {
            do {
                try await radioManager.setBeaconSettings(updatedSettings)
                try await radioManager.setAutoShareLocationChannel(beaconTransmitChannel)
                try await radioManager.setKISSTNCEnabled(kissTNCEnabled)
                if didChangeDigitalMode {
                    try await radioManager.setDigitalSignalEnabled(isDigitalModeEnabled)
                    didChangeDigitalMode = false
                }
                if supportsAPRSPath {
                    try await radioManager.setAPRSPath(aprsPath)
                }
                self.settings = updatedSettings
                isSaving = false
            } catch {
                print("Error saving beacon settings: \(error)")
                self.loadError = error.localizedDescription
                isSaving = false
            }
        }
    }

    private var locationBeaconingFooter: String {
        if smartBeaconEnabled {
            return "Smart Beacon uses this value as its minimum interval. The radio stores it in 10-second steps."
        }
        return "Choose a fixed interval. Turning location sharing on never writes a zero-second interval."
    }

    private var smartBeaconFooter: String {
        if supportsSmartBeaconIntervals {
            return "Smart Beacon adjusts timing based on movement. Minimum Interval is set in Location Beaconing; maximum is stored separately by the radio."
        }
        return "This firmware supports Smart Beacon on/off but does not report a separate maximum interval."
    }

    private let commonAPRSPaths = [
        "WIDE1-1,WIDE2-1",
        "WIDE1-1,WIDE2-2",
        "WIDE2-1",
        "WIDE2-2",
        "ARISS,SGATE,WIDE2-1"
    ]
}

#Preview {
    NavigationView {
        BeaconSettingsView()
            .environmentObject(RadioManager())
    }
}
