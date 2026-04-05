import SwiftUI

struct BLECaptureView: View {
    @AppStorage(BLECaptureStore.defaultsKey) private var captureEnabled = BLECaptureStore.defaultEnabled
    @State private var files: [BLECaptureFileInfo] = []
    @State private var isWorking = false

    var body: some View {
        Form {
            Section {
                Toggle("Capture BLE Traffic", isOn: $captureEnabled)
                    .onChange(of: captureEnabled) { _, newValue in
                        Task {
                            await BLECaptureStore.shared.setEnabled(newValue)
                            await BLECaptureStore.shared.recordNote(
                                category: "capture_toggle",
                                message: newValue ? "Capture enabled" : "Capture disabled"
                            )
                            await refresh()
                        }
                    }

                if captureEnabled {
                    Label("Recording raw TX/RX packets plus disconnects, service changes, decode errors, and unknown protocol payloads.", systemImage: "record.circle")
                        .foregroundStyle(.secondary)
                } else {
                    Label("Capture is off. Turn it on before reproducing an issue.", systemImage: "pause.circle")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Capture", systemImage: "waveform.badge.magnifyingglass")
            }

            Section {
                Button("Refresh Capture Files") {
                    Task { await refresh() }
                }

                Button("Clear Capture Files", role: .destructive) {
                    Task {
                        isWorking = true
                        await BLECaptureStore.shared.clear()
                        await refresh()
                        isWorking = false
                    }
                }
                .disabled(files.isEmpty || isWorking)
            } header: {
                Label("Manage", systemImage: "slider.horizontal.3")
            }

            Section {
                if files.isEmpty {
                    Text("No capture files yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(files) { file in
                        ShareLink(item: file.url) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(file.title)
                                    Text(file.sizeDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Label("Export", systemImage: "square.and.arrow.up")
            } footer: {
                Text("Workflow: enable capture, reproduce the problem, then share the current capture file. The JSONL includes raw BLE packets and structured notes for disconnects, unknown packets, event payloads, and protocol decode failures.")
            }
        }
        .navigationTitle("BLE Capture")
        .task {
            await BLECaptureStore.shared.setEnabled(captureEnabled)
            await refresh()
        }
    }

    @MainActor
    private func refresh() async {
        isWorking = true
        files = await BLECaptureStore.shared.availableFiles()
        isWorking = false
    }
}
