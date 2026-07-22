import SwiftUI

struct APRSIGateSettingsView: View {
    @EnvironmentObject private var radioManager: RadioManager
    @StateObject private var settingsStore = APRSIGateSettingsStore.shared
    @StateObject private var gateway = APRSIGateService.shared

    var body: some View {
        Form {
            Section {
                Toggle("Enable iGate", isOn: binding(\.isEnabled))

                HStack {
                    Text("Status")
                    Spacer()
                    Text(gateway.status)
                        .foregroundColor(.secondary)
                }

                if let lastError = gateway.lastError {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            }

            Section("APRS-IS Login") {
                TextField("Callsign", text: binding(\.callsign))
                    .textInputAutocapitalization(.characters)
                    .disableAutocorrection(true)

                SecureField("Passcode", text: binding(\.passcode))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                Button("Use Calculated Passcode") {
                    settingsStore.configuration.passcode = APRSISPasscode.value(for: settingsStore.configuration.callsign)
                }
                .disabled(settingsStore.configuration.callsign.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section("Server") {
                Picker("Regional Server", selection: binding(\.server)) {
                    ForEach(APRSIGateConfiguration.servers.keys.sorted(), id: \.self) { label in
                        Text(label).tag(APRSIGateConfiguration.servers[label]!)
                    }
                }

                Picker("Receiving Range", selection: binding(\.receivingRangeKilometers)) {
                    ForEach([50, 100, 200, 500, 1_000, 2_000, 5_000, 20_000], id: \.self) { range in
                        Text(range == 20_000 ? "Worldwide" : "\(range) km").tag(range)
                    }
                }
            }

            Section {
                Toggle("Radio to Internet", isOn: binding(\.radioToInternet))
                Toggle("Internet to Radio", isOn: binding(\.internetToRadio))
                Toggle("Receive APRS Messages", isOn: binding(\.receiveMessages))
            } header: {
                Text("Routing")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Incoming APRS-IS traffic is sent to the radio at most twice per minute.")
                    if gateway.suppressedInternetPacketCount > 0 {
                        Text("\(gateway.suppressedInternetPacketCount) incoming packet\(gateway.suppressedInternetPacketCount == 1 ? "" : "s") suppressed to protect RF airtime.")
                    }
                }
            }

            Section {
                Button("Apply iGate") {
                    gateway.apply(
                        configuration: settingsStore.configuration,
                        radioController: radioManager.radioController
                    )
                }
                .disabled(settingsStore.configuration.isEnabled && !radioManager.isConnected)

                if settingsStore.configuration.isEnabled {
                    Button("Stop iGate", role: .destructive) {
                        settingsStore.configuration.isEnabled = false
                        gateway.apply(
                            configuration: settingsStore.configuration,
                            radioController: radioManager.radioController
                        )
                    }
                }
            }
        }
        .navigationTitle("APRS Internet Gateway")
        .scrollDismissesKeyboard(.interactively)
        .fieldHTKeyboardDismissal()
        .onAppear {
            if settingsStore.configuration.callsign.isEmpty {
                Task {
                    guard let beaconSettings = try? await radioManager.getBeaconSettings() else { return }
                    let suffix = beaconSettings.aprsSSID == 0 ? "" : "-\(beaconSettings.aprsSSID)"
                    settingsStore.configuration.callsign = beaconSettings.aprsCallsign + suffix
                }
            }
            gateway.apply(configuration: settingsStore.configuration, radioController: radioManager.radioController)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<APRSIGateConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.configuration[keyPath: keyPath] },
            set: { settingsStore.configuration[keyPath: keyPath] = $0 }
        )
    }
}
