import Combine
import Foundation
import SwiftUI

@MainActor
final class AdvancedFrequencyScanStore: ObservableObject {
    struct ScanHit: Codable, Identifiable, Equatable {
        let id: UUID
        let frequencyMHz: Double
        let rxSubAudio: SubAudio?
        let txSubAudio: SubAudio?
        let detectedAt: Date

        init(
            id: UUID = UUID(),
            frequencyMHz: Double,
            rxSubAudio: SubAudio?,
            txSubAudio: SubAudio?,
            detectedAt: Date = .now
        ) {
            self.id = id
            self.frequencyMHz = frequencyMHz
            self.rxSubAudio = rxSubAudio
            self.txSubAudio = txSubAudio
            self.detectedAt = detectedAt
        }

        private enum CodingKeys: String, CodingKey {
            case id, frequencyMHz, rxSubAudio, txSubAudio, detectedAt
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(UUID.self, forKey: .id)
            frequencyMHz = try values.decode(Double.self, forKey: .frequencyMHz)
            rxSubAudio = try values.decodeIfPresent(SubAudio.self, forKey: .rxSubAudio)
            txSubAudio = try values.decodeIfPresent(SubAudio.self, forKey: .txSubAudio)
            detectedAt = try values.decode(Date.self, forKey: .detectedAt)
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(id, forKey: .id)
            try values.encode(frequencyMHz, forKey: .frequencyMHz)
            try values.encodeIfPresent(rxSubAudio, forKey: .rxSubAudio)
            try values.encodeIfPresent(txSubAudio, forKey: .txSubAudio)
            try values.encode(detectedAt, forKey: .detectedAt)
        }

        var toneSummary: String? {
            let labels = [
                rxSubAudio.map { "RX \($0.scanToneLabel)" },
                txSubAudio.map { "TX \($0.scanToneLabel)" }
            ].compactMap { $0 }
            return labels.isEmpty ? nil : labels.joined(separator: "  ")
        }
    }

    struct BandPreset: Identifiable {
        let name: String
        let startMHz: Double
        let endMHz: Double
        let defaultStepKHz: Double

        var id: String { name }
    }

    private struct StoredValues: Codable {
        var startMHz: Double
        var endMHz: Double
        var currentMHz: Double
        var scanStepKHz: Double
        var fineTuningStepKHz: Double
        var autoContinue: Bool?
        var pauseOnSignal: Bool?
        var hits: [ScanHit]?
    }

    static let scanStepOptions: [Double] = [5, 6.25, 10, 12.5, 15, 25]
    static let fineTuningStepOptions: [Double] = [0.5, 5, 6.25, 10, 12.5, 15, 25]
    static let maxRecentHits = 24
    static let bandPresets: [BandPreset] = [
        BandPreset(name: "2 m", startMHz: 144, endMHz: 148, defaultStepKHz: 12.5),
        BandPreset(name: "1.25 m", startMHz: 220, endMHz: 225, defaultStepKHz: 12.5),
        BandPreset(name: "70 cm", startMHz: 420, endMHz: 450, defaultStepKHz: 25),
        BandPreset(name: "NOAA Weather", startMHz: 162.400, endMHz: 162.550, defaultStepKHz: 25),
        BandPreset(name: "Wide VHF/UHF", startMHz: 136, endMHz: 520, defaultStepKHz: 25)
    ]

    private static let defaultsKey = "advancedFrequencyScan"

    @Published private(set) var startMHz: Double
    @Published private(set) var endMHz: Double
    @Published private(set) var currentMHz: Double
    @Published var scanStepKHz: Double { didSet { persist() } }
    @Published var fineTuningStepKHz: Double { didSet { persist() } }
    @Published var autoContinue: Bool { didSet { persist() } }
    @Published private(set) var hits: [ScanHit]

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
            autoContinue = saved.autoContinue ?? saved.pauseOnSignal ?? false
            hits = Array((saved.hits ?? []).prefix(Self.maxRecentHits))
        } else {
            startMHz = 136
            endMHz = 520
            currentMHz = 146.520
            scanStepKHz = 12.5
            fineTuningStepKHz = 0.5
            autoContinue = false
            hits = []
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

    @discardableResult
    func move(direction: Int, usingFineTuning: Bool) -> Bool {
        let stepMHz = (usingFineTuning ? fineTuningStepKHz : scanStepKHz) / 1_000
        let candidate = currentMHz + (Double(direction) * stepMHz)
        let boundedCandidate = min(max(candidate, startMHz), endMHz)
        let moved = abs(boundedCandidate - currentMHz) > 0.000_001
        currentMHz = boundedCandidate
        persist()
        return moved
    }

    func setCurrentMHz(_ value: Double) {
        currentMHz = min(max(value, startMHz), endMHz)
        persist()
    }

    func setMonitoringMHz(_ value: Double) {
        currentMHz = value
        persist()
    }

    func prepareForScan(direction: Int) {
        guard currentMHz < startMHz || currentMHz > endMHz else { return }
        currentMHz = direction > 0 ? startMHz : endMHz
        persist()
    }

    func applyPreset(_ preset: BandPreset) {
        startMHz = preset.startMHz
        endMHz = preset.endMHz
        currentMHz = preset.startMHz
        scanStepKHz = preset.defaultStepKHz
        persist()
    }

    func applySupportedRange(_ range: FrequencyRange) {
        startMHz = range.lowerMHz
        endMHz = range.upperMHz
        currentMHz = min(max(currentMHz, startMHz), endMHz)
        persist()
    }

    func constrain(to ranges: [FrequencyRange]) {
        guard !ranges.isEmpty else { return }
        guard !ranges.contains(where: { $0.contains(startMHz) && $0.contains(endMHz) }) else { return }

        if let currentRange = ranges.first(where: { $0.contains(currentMHz) }) {
            applySupportedRange(currentRange)
        } else if let firstRange = ranges.first {
            applySupportedRange(firstRange)
        }
    }

    func recordHit(
        frequencyMHz: Double,
        rxSubAudio: SubAudio?,
        txSubAudio: SubAudio?
    ) {
        hits.removeAll { abs($0.frequencyMHz - frequencyMHz) < 0.000_001 }
        hits.insert(
            ScanHit(
                id: UUID(),
                frequencyMHz: frequencyMHz,
                rxSubAudio: rxSubAudio,
                txSubAudio: txSubAudio,
                detectedAt: .now
            ),
            at: 0
        )
        hits = Array(hits.prefix(Self.maxRecentHits))
        persist()
    }

    func deleteHits(at offsets: IndexSet) {
        hits.remove(atOffsets: offsets)
        persist()
    }

    func clearHits() {
        hits = []
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
            pauseOnSignal: nil,
            hits: hits
        )
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
private enum ScanOperationState: Equatable {
    case idle
    case scanning(direction: Int)
    case held(direction: Int)

    var direction: Int {
        switch self {
        case .idle: 1
        case .scanning(let direction), .held(let direction): direction
        }
    }

    var statusText: String {
        switch self {
        case .idle: "Ready"
        case .scanning(let direction): direction > 0 ? "Scanning up" : "Scanning down"
        case .held: "Held on signal"
        }
    }
}

struct AdvancedFrequencyScanView: View {
    @EnvironmentObject private var radioManager: RadioManager
    @StateObject private var scanStore = AdvancedFrequencyScanStore()
    @State private var operation: ScanOperationState = .idle
    @State private var scanMonitoringTask: Task<Void, Never>?
    @State private var heldMonitoringTask: Task<Void, Never>?
    @State private var scanError: String?
    @State private var scanNotice: String?
    @State private var currentReceiveTone: SubAudio?
    @State private var currentTransmitTone: SubAudio?
    @State private var isShowingSetup = false
    @State private var hitToSave: AdvancedFrequencyScanStore.ScanHit?
    @State private var supportedReceiveRanges: [FrequencyRange] = []
    @State private var lastFrequencyScanNotificationAt: Date?

    private var isScanning: Bool {
        if case .scanning = operation { return true }
        return false
    }

    private var isHeld: Bool {
        if case .held = operation { return true }
        return false
    }

    private var isNotificationSupported: Bool {
        radioManager.radioController?.supportsFrequencyScanStatusNotifications == true
    }

    var body: some View {
        List {
            liveFrequency

            Section("Scan") {
                scanControls
            }

            if case .held = operation {
                Section("Fine Tune") {
                    fineTuneControls
                }
            }

            recentHits

            if let scanNotice {
                Section {
                    Label(scanNotice, systemImage: "stop.circle")
                        .foregroundStyle(.secondary)
                }
            }

            if let scanError {
                Section {
                    Label(scanError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Advanced Scan")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingSetup = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Scan setup")
                .disabled(isScanning)
            }
        }
        .sheet(isPresented: $isShowingSetup) {
            AdvancedScanSetupView(
                store: scanStore,
                supportedReceiveRanges: supportedReceiveRanges
            )
        }
        .sheet(item: $hitToSave) { hit in
            ScanHitSaveSheet(hit: hit)
                .environmentObject(radioManager)
        }
        .onAppear(perform: loadSupportedRanges)
        .onChange(of: radioManager.isConnected) { _, isConnected in
            if isConnected {
                loadSupportedRanges()
            } else {
                supportedReceiveRanges = []
            }
        }
        .onDisappear(perform: stopScan)
    }

    private var liveFrequency: some View {
        Section {
            VStack(spacing: 12) {
                Label(operation.statusText, systemImage: statusSymbol)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(statusColor)

                Text(String(format: "%.4f MHz", scanStore.currentMHz))
                    .font(.system(size: 34, weight: .semibold, design: .monospaced))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)

                LabeledContent("Range") {
                    Text(String(format: "%.3f - %.3f MHz", scanStore.startMHz, scanStore.endMHz))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Scan Step") {
                    Text(stepLabel(scanStore.scanStepKHz))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if isScanning || isHeld {
                    LabeledContent("RX Tone") {
                        Text(currentReceiveTone?.scanToneLabel ?? "None")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("TX Tone") {
                        Text(currentTransmitTone?.scanToneLabel ?? "None")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var scanControls: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                scanControlButtons
            }
        } else {
            scanControlButtons
        }
    }

    private var scanControlButtons: some View {
        HStack(spacing: 12) {
            scanActionButton(
                title: "Down",
                systemImage: "backward.fill",
                action: { startRapidScan(direction: -1) }
            )

            switch operation {
            case .scanning:
                scanActionButton(
                    title: "Hold",
                    systemImage: "pause.fill",
                    action: holdScan
                )
            case .held:
                scanActionButton(
                    title: "Resume",
                    systemImage: "play.fill",
                    action: resumeScan
                )
            case .idle:
                scanActionButton(
                    title: "Hold",
                    systemImage: "pause.fill",
                    action: {},
                    isEnabled: false
                )
            }

            scanActionButton(
                title: "Up",
                systemImage: "forward.fill",
                action: { startRapidScan(direction: 1) }
            )
        }
    }

    private var fineTuneControls: some View {
        HStack {
            fineTuneButton(title: "Fine tune down", systemImage: "minus", direction: -1)

            VStack(spacing: 2) {
                Text("Fine Tune")
                    .font(.subheadline.weight(.medium))
                Text(stepLabel(scanStore.fineTuningStepKHz))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            fineTuneButton(title: "Fine tune up", systemImage: "plus", direction: 1)
        }
    }

    @ViewBuilder
    private var recentHits: some View {
        Section {
            if scanStore.hits.isEmpty {
                ContentUnavailableView(
                    "No hits yet",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text("Detected frequencies appear here while scanning.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ForEach(scanStore.hits) { hit in
                    hitRow(hit)
                }
                .onDelete(perform: scanStore.deleteHits)
            }
        } header: {
            HStack {
                Text("Recent Hits")
                Spacer()
                if !scanStore.hits.isEmpty {
                    Button("Clear", role: .destructive) {
                        scanStore.clearHits()
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private func hitRow(_ hit: AdvancedFrequencyScanStore.ScanHit) -> some View {
        HStack {
            Button {
                tuneAndMonitor(hit)
            } label: {
                HStack {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.4f MHz", hit.frequencyMHz))
                            .font(.body.monospacedDigit())
                        if let toneSummary = hit.toneSummary {
                            Text(toneSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(hit.detectedAt, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Button {
                hitToSave = hit
            } label: {
                Image(systemName: "tray.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Save hit to memory")
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint("Swipe to delete this hit.")
    }

    @ViewBuilder
    private func scanActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void,
        isEnabled: Bool = true
    ) -> some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                scanActionLabel(title: title, systemImage: systemImage)
            }
            .buttonStyle(.glass)
            .disabled(!isEnabled || !radioManager.isConnected || radioManager.isBusy)
        } else {
            Button(action: action) {
                scanActionLabel(title: title, systemImage: systemImage)
            }
            .buttonStyle(.bordered)
            .disabled(!isEnabled || !radioManager.isConnected || radioManager.isBusy)
        }
    }

    private func scanActionLabel(title: String, systemImage: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.headline)
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
    }

    private func fineTuneButton(title: String, systemImage: String, direction: Int) -> some View {
        Button {
            fineTune(direction: direction)
        } label: {
            Image(systemName: systemImage)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.bordered)
        .disabled(!radioManager.isConnected || radioManager.isBusy)
        .accessibilityLabel(title)
    }

    private var statusSymbol: String {
        switch operation {
        case .idle: "dot.radiowaves.left.and.right"
        case .scanning: "wave.3.right"
        case .held: "antenna.radiowaves.left.and.right"
        }
    }

    private var statusColor: Color {
        switch operation {
        case .scanning: .accentColor
        case .idle, .held: .secondary
        }
    }

    private func startRapidScan(direction: Int) {
        guard radioManager.isConnected, !radioManager.isBusy else { return }
        guard supportedReceiveRanges.isEmpty || supportedReceiveRanges.contains(where: {
            $0.contains(scanStore.startMHz) && $0.contains(scanStore.endMHz)
        }) else {
            scanError = "Choose a receive range supported by this radio before scanning."
            isShowingSetup = true
            return
        }

        scanError = nil
        scanNotice = nil
        scanStore.prepareForScan(direction: direction)
        lastFrequencyScanNotificationAt = nil
        scanMonitoringTask?.cancel()
        heldMonitoringTask?.cancel()
        heldMonitoringTask = nil
        operation = .scanning(direction: direction)
        let mode: FrequencyMode = direction > 0 ? .scanUp : .scanDown

        scanMonitoringTask = Task { @MainActor in
            do {
                try await sendFrequencyMode(mode)
                try await monitorNativeScan(direction: direction, mode: mode)
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled {
                    operation = .idle
                    scanMonitoringTask = nil
                    scanError = "Scan stopped: \(error.localizedDescription)"
                }
            }
        }
    }

    private func holdScan() {
        guard isScanning else { return }
        let direction = operation.direction
        scanMonitoringTask?.cancel()
        scanMonitoringTask = nil
        operation = .held(direction: direction)
        applyFrequencyMode(.exact)
        startHeldMonitoring(direction: direction)
    }

    private func resumeScan() {
        guard case .held(let direction) = operation else { return }
        startRapidScan(direction: direction)
    }

    private func stopRapidScan() {
        stopScan()
    }

    private func stopScan() {
        scanMonitoringTask?.cancel()
        scanMonitoringTask = nil
        heldMonitoringTask?.cancel()
        heldMonitoringTask = nil
        lastFrequencyScanNotificationAt = nil
        operation = .idle
        guard radioManager.isConnected else { return }
        applyFrequencyMode(.off)
    }

    private func fineTune(direction: Int) {
        if isScanning {
            scanMonitoringTask?.cancel()
            scanMonitoringTask = nil
        }
        _ = scanStore.move(direction: direction, usingFineTuning: true)
        operation = .held(direction: operation.direction)
        applyFrequencyMode(.exact)
        startHeldMonitoring(direction: operation.direction)
    }

    private func tuneAndMonitor(_ hit: AdvancedFrequencyScanStore.ScanHit) {
        if isScanning {
            scanMonitoringTask?.cancel()
            scanMonitoringTask = nil
        }
        scanNotice = nil
        scanStore.setMonitoringMHz(hit.frequencyMHz)
        currentReceiveTone = hit.rxSubAudio
        currentTransmitTone = hit.txSubAudio
        operation = .held(direction: operation.direction)
        applyFrequencyMode(.exact)
        startHeldMonitoring(direction: operation.direction)
    }

    private func applyFrequencyMode(_ mode: FrequencyMode) {
        scanError = nil
        Task { @MainActor in
            do {
                try await sendFrequencyMode(mode)
            } catch {
                scanError = "Unable to update frequency scan: \(error.localizedDescription)"
            }
        }
    }

    private func sendFrequencyMode(_ mode: FrequencyMode) async throws {
        try await radioManager.setFrequencyScan(
            frequencyMHz: scanStore.currentMHz,
            mode: mode,
            stepKHz: scanStore.scanStepKHz
        )
    }

    private func monitorNativeScan(direction: Int, mode: FrequencyMode) async throws {
        while !Task.isCancelled && isScanning {
            try await Task.sleep(nanoseconds: 100_000_000)
            guard let status = try await nextFrequencyScanStatus() else { continue }

            if hasReachedScanBoundary(status, direction: direction) {
                updateLiveStatus(status)
                if status.isTuned {
                    scanStore.recordHit(
                        frequencyMHz: status.rxMHz,
                        rxSubAudio: status.rxSubAudio,
                        txSubAudio: status.txSubAudio
                    )
                }
                try await stopAtScanBoundary(direction: direction)
                continue
            }

            updateLiveStatus(status)

            if status.isTuned {
                scanStore.recordHit(
                    frequencyMHz: status.rxMHz,
                    rxSubAudio: status.rxSubAudio,
                    txSubAudio: status.txSubAudio
                )
            }

            guard status.mode == mode else {
                operation = status.isTuned ? .held(direction: direction) : .idle
                scanMonitoringTask = nil
                return
            }

            guard status.isTuned else { continue }

            if scanStore.autoContinue {
                guard scanStore.move(direction: direction, usingFineTuning: false) else {
                    try await stopAtScanBoundary(direction: direction)
                    return
                }
                try await sendFrequencyMode(mode)
            } else {
                operation = .held(direction: direction)
                scanMonitoringTask = nil
                startHeldMonitoring(direction: direction)
                return
            }
        }
    }

    private func startHeldMonitoring(direction: Int) {
        heldMonitoringTask?.cancel()
        heldMonitoringTask = Task { @MainActor in
            do {
                try await monitorHeldFrequency(direction: direction)
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled {
                    heldMonitoringTask = nil
                    scanError = "Unable to monitor held frequency: \(error.localizedDescription)"
                }
            }
        }
    }

    private func monitorHeldFrequency(direction: Int) async throws {
        while !Task.isCancelled && isHeld {
            try await Task.sleep(nanoseconds: 500_000_000)
            guard let status = try await nextFrequencyScanStatus() else { continue }
            updateLiveStatus(status)

            if status.isTuned {
                scanStore.recordHit(
                    frequencyMHz: status.rxMHz,
                    rxSubAudio: status.rxSubAudio,
                    txSubAudio: status.txSubAudio
                )
            }

            if status.mode == .off {
                operation = .idle
                heldMonitoringTask = nil
                return
            }
        }
    }

    private func updateLiveStatus(_ status: FrequencyModeStatus) {
        if isScanning {
            scanStore.setCurrentMHz(status.rxMHz)
        } else {
            scanStore.setMonitoringMHz(status.rxMHz)
        }
        currentReceiveTone = status.rxSubAudio
        currentTransmitTone = status.txSubAudio
    }

    private func hasReachedScanBoundary(
        _ status: FrequencyModeStatus,
        direction: Int
    ) -> Bool {
        direction > 0
            ? status.rxMHz >= scanStore.endMHz
            : status.rxMHz <= scanStore.startMHz
    }

    private func stopAtScanBoundary(direction: Int) async throws {
        scanStore.setCurrentMHz(direction > 0 ? scanStore.endMHz : scanStore.startMHz)
        operation = .idle
        scanMonitoringTask = nil
        scanNotice = "Reached scan boundary."
        try await sendFrequencyMode(.off)
    }

    private func loadSupportedRanges() {
        guard radioManager.isConnected else { return }

        Task { @MainActor in
            do {
                let ranges = try await radioManager.getFrequencyRanges().receiveFMRanges
                supportedReceiveRanges = ranges
                scanStore.constrain(to: ranges)
            } catch {
                // Older firmware can omit command 39; manual band-plan entry remains available.
                supportedReceiveRanges = []
            }
        }
    }

    /// Prefer status-change events when firmware advertises capability 143. If that
    /// stream is quiet, use the stock app's command-36 polling fallback.
    private func nextFrequencyScanStatus() async throws -> FrequencyModeStatus? {
        if isNotificationSupported,
           let controller = radioManager.radioController,
           let updatedAt = controller.frequencyScanStatusUpdatedAt,
           let notificationStatus = controller.frequencyScanStatus {
            if updatedAt != lastFrequencyScanNotificationAt {
                lastFrequencyScanNotificationAt = updatedAt
                return notificationStatus
            }

            if Date.now.timeIntervalSince(updatedAt) < 0.75 {
                return nil
            }
        }

        return try await radioManager.getFrequencyScanStatus()
    }

    private func stepLabel(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value)) kHz" : "\(value) kHz"
    }
}

private struct AdvancedScanSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: AdvancedFrequencyScanStore
    let supportedReceiveRanges: [FrequencyRange]

    var body: some View {
        NavigationStack {
            Form {
                Section("Frequency Range") {
                    TextField(
                        "Start MHz",
                        value: Binding(
                            get: { store.startMHz },
                            set: { store.setStartMHz($0) }
                        ),
                        format: .number.precision(.fractionLength(3))
                    )
                    .keyboardType(.decimalPad)

                    TextField(
                        "End MHz",
                        value: Binding(
                            get: { store.endMHz },
                            set: { store.setEndMHz($0) }
                        ),
                        format: .number.precision(.fractionLength(3))
                    )
                    .keyboardType(.decimalPad)
                }

                if !supportedReceiveRanges.isEmpty {
                    Section {
                        ForEach(supportedReceiveRanges) { range in
                            Button {
                                store.applySupportedRange(range)
                            } label: {
                                HStack {
                                    Text(range.displayName)
                                    Spacer()
                                    if range.contains(store.startMHz) && range.contains(store.endMHz) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Radio Ranges")
                    } footer: {
                        Text("Receive ranges reported by the connected radio.")
                    }
                }

                Section {
                    ForEach(AdvancedFrequencyScanStore.bandPresets) { preset in
                        Button {
                            store.applyPreset(preset)
                            store.constrain(to: supportedReceiveRanges)
                        } label: {
                            HStack {
                                Text(preset.name)
                                Spacer()
                                Text(
                                    String(
                                        format: "%.3f - %.3f MHz",
                                        preset.startMHz,
                                        preset.endMHz
                                    )
                                )
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Band Presets")
                } footer: {
                    Text("Presets change the range and scan step. Confirm your local band plan before transmitting.")
                }

                Section("Steps") {
                    Picker("Scan Step", selection: $store.scanStepKHz) {
                        ForEach(AdvancedFrequencyScanStore.scanStepOptions, id: \.self) { step in
                            Text(stepLabel(step)).tag(step)
                        }
                    }

                    Picker("Fine Tune Step", selection: $store.fineTuningStepKHz) {
                        ForEach(AdvancedFrequencyScanStore.fineTuningStepOptions, id: \.self) { step in
                            Text(stepLabel(step)).tag(step)
                        }
                    }
                }

                Section {
                    Toggle("Continue after a signal", isOn: $store.autoContinue)
                } footer: {
                    Text("When off, the radio holds on a detected signal until you choose Resume.")
                }
            }
            .navigationTitle("Scan Setup")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func stepLabel(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value)) kHz" : "\(value) kHz"
    }
}

private struct ScanHitSaveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var radioManager: RadioManager

    let hit: AdvancedFrequencyScanStore.ScanHit

    @State private var groupIndex = 0
    @State private var slot = 0
    @State private var existingChannel: Channel?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var isShowingOverwriteConfirmation = false

    private var maximumSlot: Int {
        max(radioManager.memoryChannelCount - 1, 0)
    }

    private var hasMemoryGroups: Bool {
        !radioManager.regionNames.isEmpty && radioManager.memoryChannelCount > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Detected") {
                    LabeledContent("Frequency") {
                        Text(String(format: "%.4f MHz", hit.frequencyMHz))
                            .monospacedDigit()
                    }
                    if let rxSubAudio = hit.rxSubAudio {
                        LabeledContent("Receive Tone", value: rxSubAudio.scanToneLabel)
                    }
                    if let txSubAudio = hit.txSubAudio {
                        LabeledContent("Transmit Tone", value: txSubAudio.scanToneLabel)
                    }
                }

                Section("Save To") {
                    Picker("Memory Group", selection: $groupIndex) {
                        ForEach(Array(radioManager.regionNames.enumerated()), id: \.offset) { index, name in
                            Text(name).tag(index)
                        }
                    }

                    Stepper(value: $slot, in: 0...maximumSlot) {
                        LabeledContent("Channel") {
                            Text(String(format: "%03d", slot + 1))
                                .monospacedDigit()
                        }
                    }
                }

                if let existingChannel, !existingChannel.isEmptyMemorySlot {
                    Section {
                        LabeledContent("Existing Frequency") {
                            Text(String(format: "%.4f MHz", existingChannel.rxFreq))
                                .monospacedDigit()
                        }
                        if !existingChannel.name.isEmpty {
                            LabeledContent("Existing Name", value: existingChannel.name)
                        }
                    } header: {
                        Text("Existing Channel")
                    } footer: {
                        Text("Saving will replace this channel after confirmation.")
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Save Scan Hit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        checkTargetSlot()
                    } label: {
                        if isWorking {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!hasMemoryGroups || isWorking || !radioManager.isConnected)
                }
            }
            .onAppear {
                groupIndex = min(radioManager.activeRegionIndex, max(radioManager.regionNames.count - 1, 0))
            }
            .onChange(of: groupIndex) {
                existingChannel = nil
            }
            .onChange(of: slot) {
                existingChannel = nil
            }
            .confirmationDialog(
                "Replace Existing Channel?",
                isPresented: $isShowingOverwriteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Replace", role: .destructive) {
                    saveHit()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Channel \(slot + 1) in \(radioManager.regionNames[safe: groupIndex] ?? "this group") will be replaced.")
            }
        }
    }

    private func checkTargetSlot() {
        errorMessage = nil
        isWorking = true

        Task {
            do {
                let channel = try await radioManager.memoryChannel(inRegion: groupIndex, slot: slot)
                existingChannel = channel
                isWorking = false

                if channel.isEmptyMemorySlot {
                    saveHit()
                } else {
                    isShowingOverwriteConfirmation = true
                }
            } catch {
                isWorking = false
                errorMessage = "Unable to inspect this channel: \(error.localizedDescription)"
            }
        }
    }

    private func saveHit() {
        errorMessage = nil
        isWorking = true

        Task {
            do {
                try await radioManager.saveScanHit(
                    frequencyMHz: hit.frequencyMHz,
                    rxSubAudio: hit.rxSubAudio,
                    inRegion: groupIndex,
                    slot: slot
                )
                dismiss()
            } catch {
                isWorking = false
                errorMessage = "Unable to save this channel: \(error.localizedDescription)"
            }
        }
    }
}

private extension Channel {
    var isEmptyMemorySlot: Bool {
        rxFreq <= 0 && txFreq <= 0 && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private extension SubAudio {
    var scanToneLabel: String {
        switch self {
        case .frequency(let hertz):
            return String(format: "PL %.1f Hz", hertz)
        case .dcs(let dcs):
            return String(format: "DCS %03d", dcs.n)
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
