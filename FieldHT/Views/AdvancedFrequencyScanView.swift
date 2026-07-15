import Combine
import SwiftUI

@MainActor
final class AdvancedFrequencyScanStore: ObservableObject {
    private struct StoredValues: Codable {
        var startMHz: Double
        var endMHz: Double
        var currentMHz: Double
        var scanStepKHz: Double
        var fineTuningStepKHz: Double
    }

    static let scanStepOptions: [Double] = [5, 6.25, 10, 12.5, 15, 25]
    static let fineTuningStepOptions: [Double] = [0.5, 5, 6.25, 10, 12.5, 15, 25]

    private static let defaultsKey = "advancedFrequencyScan"

    @Published private(set) var startMHz: Double
    @Published private(set) var endMHz: Double
    @Published private(set) var currentMHz: Double
    @Published var scanStepKHz: Double { didSet { persist() } }
    @Published var fineTuningStepKHz: Double { didSet { persist() } }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(StoredValues.self, from: data),
           saved.startMHz > 0,
           saved.endMHz > saved.startMHz {
            startMHz = saved.startMHz
            endMHz = saved.endMHz
            currentMHz = min(max(saved.currentMHz, saved.startMHz), saved.endMHz)
            scanStepKHz = Self.scanStepOptions.contains(saved.scanStepKHz) ? saved.scanStepKHz : 12.5
            fineTuningStepKHz = Self.fineTuningStepOptions.contains(saved.fineTuningStepKHz) ? saved.fineTuningStepKHz : 0.5
        } else {
            startMHz = 136
            endMHz = 520
            currentMHz = 146.520
            scanStepKHz = 12.5
            fineTuningStepKHz = 0.5
        }
    }

    func setStartMHz(_ value: Double) {
        guard value > 0, value < endMHz else { return }
        startMHz = value
        currentMHz = min(max(currentMHz, startMHz), endMHz)
        persist()
    }

    func setEndMHz(_ value: Double) {
        guard value > startMHz else { return }
        endMHz = value
        currentMHz = min(max(currentMHz, startMHz), endMHz)
        persist()
    }

    func move(direction: Int, usingFineTuning: Bool) {
        let stepMHz = (usingFineTuning ? fineTuningStepKHz : scanStepKHz) / 1_000
        let candidate = currentMHz + (Double(direction) * stepMHz)

        if candidate > endMHz {
            currentMHz = startMHz
        } else if candidate < startMHz {
            currentMHz = endMHz
        } else {
            currentMHz = candidate
        }

        persist()
    }

    private func persist() {
        let values = StoredValues(
            startMHz: startMHz,
            endMHz: endMHz,
            currentMHz: currentMHz,
            scanStepKHz: scanStepKHz,
            fineTuningStepKHz: fineTuningStepKHz
        )
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

struct AdvancedFrequencyScanView: View {
    @EnvironmentObject private var radioManager: RadioManager
    @StateObject private var scanStore = AdvancedFrequencyScanStore()

    var body: some View {
        Form {
            Section {
                TextField(
                    "Start",
                    value: Binding(
                        get: { scanStore.startMHz },
                        set: { scanStore.setStartMHz($0) }
                    ),
                    format: .number.precision(.fractionLength(3))
                )
                .keyboardType(.decimalPad)

                TextField(
                    "End",
                    value: Binding(
                        get: { scanStore.endMHz },
                        set: { scanStore.setEndMHz($0) }
                    ),
                    format: .number.precision(.fractionLength(3))
                )
                .keyboardType(.decimalPad)
            } header: {
                Text("Frequency Range")
            } footer: {
                Text("MHz. The scan wraps at the selected range limits.")
            }

            Section {
                Text(String(format: "%.4f MHz", scanStore.currentMHz))
                    .font(.title2.monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack {
                    frequencyButton(systemImage: "backward.end.fill", label: "Fine tune down") {
                        move(direction: -1, usingFineTuning: true)
                    }
                    Spacer()
                    frequencyButton(systemImage: "forward.end.fill", label: "Fine tune up") {
                        move(direction: 1, usingFineTuning: true)
                    }
                }
            } header: {
                Text("Current Frequency")
            } footer: {
                Text("Fine tune: \(stepLabel(scanStore.fineTuningStepKHz))")
            }

            Section {
                Picker("Step", selection: $scanStore.scanStepKHz) {
                    ForEach(AdvancedFrequencyScanStore.scanStepOptions, id: \.self) { step in
                        Text(stepLabel(step)).tag(step)
                    }
                }

                Picker("Fine-Tuning", selection: $scanStore.fineTuningStepKHz) {
                    ForEach(AdvancedFrequencyScanStore.fineTuningStepOptions, id: \.self) { step in
                        Text(stepLabel(step)).tag(step)
                    }
                }

                HStack {
                    frequencyButton(systemImage: "backward.fill", label: "Scan down") {
                        move(direction: -1, usingFineTuning: false)
                    }
                    Spacer()
                    frequencyButton(systemImage: "forward.fill", label: "Scan up") {
                        move(direction: 1, usingFineTuning: false)
                    }
                }
            } header: {
                Text("Scan Step")
            } footer: {
                Text("Scan step: \(stepLabel(scanStore.scanStepKHz))")
            }
        }
        .navigationTitle("Advanced Scan")
    }

    private func frequencyButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 52, height: 40)
        }
        .buttonStyle(.bordered)
        .disabled(!radioManager.isConnected || radioManager.isBusy)
        .accessibilityLabel(label)
    }

    private func move(direction: Int, usingFineTuning: Bool) {
        scanStore.move(direction: direction, usingFineTuning: usingFineTuning)
        radioManager.setFreqModeParameters(
            rxMHz: scanStore.currentMHz,
            txMHz: scanStore.currentMHz
        )
    }

    private func stepLabel(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value)) kHz" : "\(value) kHz"
    }
}
