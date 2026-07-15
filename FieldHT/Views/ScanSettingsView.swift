import SwiftUI

struct ScanSettingsView: View {
    @EnvironmentObject var radioManager: RadioManager

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    AdvancedFrequencyScanView()
                        .environmentObject(radioManager)
                } label: {
                    Label("Advanced Frequency Scan", systemImage: "dial.medium")
                }
            } footer: {
                Text("Tune across a custom frequency range with separate scan and fine-tuning steps.")
            }

            Section {
                Toggle(
                    "Scan Active Group",
                    isOn: Binding(
                        get: { radioManager.isScanning },
                        set: { radioManager.setScanning($0) }
                    )
                )
                .disabled(!radioManager.isConnected || radioManager.isBusy)
            } footer: {
                Text("Scanning steps through the programmed channels in the active memory group. Stop scan before changing groups or channels.")
            }

            if let radioController = radioManager.radioController {
                Section {
                    NavigationLink {
                        ChannelListView(radioController: radioController)
                            .environmentObject(radioManager)
                    } label: {
                        Label("Edit Channel Scan Membership", systemImage: "list.bullet")
                    }
                } footer: {
                    Text("Open a channel to review its scan setting and other channel parameters.")
                }
            }
        }
        .navigationTitle("Scan")
    }
}
