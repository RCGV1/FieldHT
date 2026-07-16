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
        var autoContinue: Bool?
        var pauseOnSignal: Bool?
    }

    static let scanStepOptions: [Double] = [5, 6.25, 10, 12.5, 15, 25]
    static let fineTuningStepOptions: [Double] = [0.5, 5, 6.25, 10, 12.5, 15, 25]

    private static let defaultsKey = "advancedFrequencyScan"

    @Published private(set) var startMHz: Double
    @Published private(set) var endMHz: Double
    @Published private(set) var currentMHz: Double
    @Published var scanStepKHz: Double { didSet { persist() } }
    @Published var fineTuningStepKHz: Double { didSet { persist() } }
    @Published var autoContinue: Bool { didSet { persist() } }

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
            autoContinue = saved.autoContinue ?? saved.pauseOnSignal ?? true
        } else {
            startMHz = 136
            endMHz = 520
            currentMHz = 146.520
            scanStepKHz = 12.5
            fineTuningStepKHz = 0.5
            autoContinue = true
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

    func setCurrentMHz(_ value: Double) {
        currentMHz = min(max(value, startMHz), endMHz)
        persist()
    }

    private func persist() {
        let values = StoredValues(
            startMHz: startMHz,
            endMHz: endMHz,
            currentMHz: currentMHz,
            scanStepKHz: scanStepKHz,
            fineTuningStepKHz: fineTuningStepKHz,
            autoContinue: autoContinue,
            pauseOnSignal: nil
        )
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

struct AdvancedFrequencyScanView: View {
    @EnvironmentObject private var radioManager: RadioManager
    @StateObject private var scanStore = AdvancedFrequencyScanStore()
    @State private var isRapidScanning = false
    @State private var scanMonitoringTask: Task<Void, Never>?
    @State private var scanError: String?

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

                Toggle("Continue after a signal", isOn: $scanStore.autoContinue)

                HStack {
                    Button {
                        startRapidScan(direction: -1)
                    } label: {
                        Label("Scan Down", systemImage: "play.fill")
                    }
                    .disabled(!canStartRapidScan)

                    Spacer()

                    if isRapidScanning {
                        Button(role: .destructive) {
                            stopRapidScan()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                    } else {
                        Button {
                            startRapidScan(direction: 1)
                        } label: {
                            Label("Scan Up", systemImage: "play.fill")
                        }
                        .disabled(!canStartRapidScan)
                    }
                }
            } header: {
                Text("Rapid Scan")
            } footer: {
                Text("Uses the radio's native scan engine. The app enforces the selected range and can continue after a received signal.")
            }

            if let scanError {
                Section {
                    Text(scanError)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Advanced Scan")
        .onDisappear(perform: stopRapidScan)
    }

    private func frequencyButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 52, height: 40)
        }
        .buttonStyle(.bordered)
        .disabled(!radioManager.isConnected || radioManager.isBusy || isRapidScanning)
        .accessibilityLabel(label)
    }

    private func move(direction: Int, usingFineTuning: Bool) {
        scanStore.move(direction: direction, usingFineTuning: usingFineTuning)
        applyFrequencyMode(.exact)
    }

    private var canStartRapidScan: Bool {
        radioManager.isConnected && !radioManager.isBusy && !isRapidScanning
    }

    private func applyFrequencyMode(_ mode: FrequencyMode) {
        scanError = nil
        Task { @MainActor in
            do {
                try await radioManager.setFrequencyScan(
                    frequencyMHz: scanStore.currentMHz,
                    mode: mode,
                    stepKHz: scanStore.scanStepKHz
                )
            } catch {
                scanError = "Unable to update frequency scan: \(error.localizedDescription)"
            }
        }
    }

    private func startRapidScan(direction: Int) {
        guard canStartRapidScan else { return }

        scanError = nil
        isRapidScanning = true
        let mode: FrequencyMode = direction > 0 ? .scanUp : .scanDown
        scanMonitoringTask = Task { @MainActor in
            do {
                try await radioManager.setFrequencyScan(
                    frequencyMHz: scanStore.currentMHz,
                    mode: mode,
                    stepKHz: scanStore.scanStepKHz
                )
                try await monitorNativeScan(direction: direction, mode: mode)
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled {
                    scanError = "Scan stopped: \(error.localizedDescription)"
                    isRapidScanning = false
                    scanMonitoringTask = nil
                }
            }
        }
    }

    private func stopRapidScan() {
        scanMonitoringTask?.cancel()
        scanMonitoringTask = nil
        isRapidScanning = false
        guard radioManager.isConnected else { return }
        applyFrequencyMode(.off)
    }

    private func monitorNativeScan(direction: Int, mode: FrequencyMode) async throws {
        while !Task.isCancelled && isRapidScanning {
            try await Task.sleep(nanoseconds: 300_000_000)
            let status = try await radioManager.getFrequencyScanStatus()
            scanStore.setCurrentMHz(status.rxMHz)

            guard status.mode == mode else {
                isRapidScanning = false
                scanMonitoringTask = nil
                return
            }

            if status.rxMHz < scanStore.startMHz || status.rxMHz > scanStore.endMHz {
                scanStore.setCurrentMHz(direction > 0 ? scanStore.startMHz : scanStore.endMHz)
                try await radioManager.setFrequencyScan(
                    frequencyMHz: scanStore.currentMHz,
                    mode: mode,
                    stepKHz: scanStore.scanStepKHz
                )
            } else if status.isTuned && scanStore.autoContinue {
                scanStore.move(direction: direction, usingFineTuning: false)
                try await radioManager.setFrequencyScan(
                    frequencyMHz: scanStore.currentMHz,
                    mode: mode,
                    stepKHz: scanStore.scanStepKHz
                )
            }
        }
    }

    private func stepLabel(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value)) kHz" : "\(value) kHz"
    }

}
