import SwiftUI

struct FMRadioView: View {
    @ObservedObject var controller: RadioController
    @AppStorage("FieldHT.fmBroadcastPresets") private var storedPresets = ""
    @State private var frequency = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var isEditingFrequency: Bool

    private var parsedFrequency: Double? { Double(frequency.replacingOccurrences(of: ",", with: ".")) }
    private var presets: [Double] {
        Array(Set(storedPresets.split(separator: ",").compactMap { Double($0) }.filter { $0.isFinite && (64...108).contains($0) })).sorted()
    }

    var body: some View {
        Form {
            Section {
                Toggle("FM Broadcast Receiver", isOn: Binding(
                    get: { controller.fmRadioStatus?.isOn ?? false },
                    set: { enabled in Task { await perform { try await controller.setFMRadioEnabled(enabled) } } }
                ))
                if let status = controller.fmRadioStatus {
                    LabeledContent("Tuned Frequency", value: String(format: "%.2f MHz", status.frequencyMHz))
                        .monospacedDigit()
                    if status.isSeeking { ProgressView("Finding a station...") }
                }
            } footer: {
                Text("Audio plays through the radio or its connected audio accessory.")
            }

            Section("Tune") {
                LabeledContent("Frequency (MHz)") {
                    TextField("64-108", text: $frequency)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isEditingFrequency)
                        .accessibilityLabel("FM frequency in megahertz")
                }
                Button("Tune Frequency") {
                    guard let value = parsedFrequency else { return }
                    isEditingFrequency = false
                    Task { await tune(value) }
                }
                .disabled(parsedFrequency.map { !$0.isFinite || !(64...108).contains($0) } ?? true)
                Button { Task { await perform { try await controller.seekFMRadio(up: false) } } } label: {
                    Label("Seek Down", systemImage: "backward.end")
                }
                .disabled(controller.fmRadioStatus?.isOn != true)
                Button { Task { await perform { try await controller.seekFMRadio(up: true) } } } label: {
                    Label("Seek Up", systemImage: "forward.end")
                }
                .disabled(controller.fmRadioStatus?.isOn != true)
            }

            Section("Saved Stations") {
                if presets.isEmpty { Text("Save a tuned station for quick access.").foregroundStyle(.secondary) }
                ForEach(presets, id: \.self) { value in
                    Button(String(format: "%.2f MHz", value)) { Task { await tune(value) } }
                        .swipeActions {
                            Button("Remove", role: .destructive) { savePresets(presets.filter { $0 != value }) }
                        }
                }
                Button("Save Current Station", systemImage: "star") {
                    guard let value = controller.fmRadioStatus?.frequencyMHz, (64...108).contains(value) else { return }
                    savePresets(presets + [value])
                }
                .disabled(controller.fmRadioStatus?.isOn != true || presets.count >= 50)
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .disabled(isWorking || controller.isPerformingMaintenance || !controller.isConnected)
        .navigationTitle("FM Radio")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isWorking { ProgressView().accessibilityLabel("Updating FM radio") }
            }
        }
        .task { await perform { try await controller.refreshFMRadioStatus() } }
        .onReceive(controller.$fmRadioStatus) { status in
            if !isEditingFrequency, let status, status.frequencyMHz > 0 { frequency = String(format: "%.2f", status.frequencyMHz) }
        }
        .fieldHTKeyboardDismissal()
    }

    private func savePresets(_ values: [Double]) {
        storedPresets = Array(Set(values)).sorted().prefix(50).map { String(format: "%.2f", $0) }.joined(separator: ",")
    }

    private func tune(_ value: Double) async {
        await perform {
            if controller.fmRadioStatus?.isOn != true { try await controller.setFMRadioEnabled(true) }
            try await controller.tuneFMRadio(value)
        }
    }

    private func perform(_ action: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do { try await action() }
        catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
    }
}
