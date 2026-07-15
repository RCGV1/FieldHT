import SwiftUI

struct ConnectionManagementView: View {
    @EnvironmentObject var radioManager: RadioManager
    @State private var showForgetConfirmation = false

    private var connectionState: String {
        if radioManager.isConnected {
            return "Connected"
        }
        if radioManager.isAutoReconnecting {
            return "Reconnecting"
        }
        if radioManager.isConnecting {
            return "Connecting"
        }
        return "Disconnected"
    }

    private var savedRadioID: String {
        guard let uuid = radioManager.lastPairedDeviceUUID else { return "None" }
        return uuid.uuidString
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Status", value: connectionState)

                Toggle("Reconnect Automatically", isOn: $radioManager.autoReconnectEnabled)
                    .disabled(radioManager.lastPairedDeviceUUID == nil)
            } header: {
                Label("Connection", systemImage: "antenna.radiowaves.left.and.right")
            } footer: {
                Text("When enabled, FieldHT retries the last saved radio after an unexpected Bluetooth disconnect.")
            }

            Section {
                LabeledContent("Saved Radio", value: savedRadioID)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if radioManager.isConnected {
                    Button(role: .destructive) {
                        radioManager.disconnect()
                    } label: {
                        Label("Disconnect Radio", systemImage: "xmark.circle")
                    }
                }

                Button(role: .destructive) {
                    showForgetConfirmation = true
                } label: {
                    Label("Forget Saved Radio", systemImage: "trash")
                }
                .disabled(radioManager.lastPairedDeviceUUID == nil)
            } header: {
                Label("Saved Radio", systemImage: "radio")
            } footer: {
                Text("Forgetting a radio removes its saved Bluetooth identifier and stops automatic reconnects.")
            }
        }
        .navigationTitle("Connection Management")
        .alert("Forget Saved Radio?", isPresented: $showForgetConfirmation) {
            Button("Forget", role: .destructive) {
                radioManager.forgetLastPairedRadio()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need to scan and connect to this radio again.")
        }
    }
}
