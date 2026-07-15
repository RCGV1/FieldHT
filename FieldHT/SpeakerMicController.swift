import Foundation
import Combine

@MainActor
public final class SpeakerMicController: ObservableObject {
    public static let bs22ProductID = 516

    private let connection: CommandConnection
    public let deviceUUID: UUID

    @Published public private(set) var deviceInfo: DeviceInfo = .empty()
    @Published public private(set) var pfConfig: PFConfig = .init()
    @Published public private(set) var supportedActions: [PFEffectType] = []
    @Published public private(set) var batteryPercent: Int = 0
    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var isConnecting: Bool = false
    @Published public private(set) var isRefreshing: Bool = false
    @Published public private(set) var isSavingPF: Bool = false
    @Published public private(set) var lastConnectedAt: Date?
    @Published public var errorMessage: String?

    private var batteryPollTask: Task<Void, Never>?
    private static let batteryPollIntervalNanoseconds: UInt64 = 180_000_000_000

    private init(deviceUUID: UUID, connection: CommandConnection) {
        self.deviceUUID = deviceUUID
        self.connection = connection
    }

    public static func newBLE(deviceUUID: UUID) -> SpeakerMicController {
        let connection = CommandConnection.newBLE(
            deviceUUID: deviceUUID,
            radioManager: nil,
            enableStateRestoration: false
        )
        return SpeakerMicController(deviceUUID: deviceUUID, connection: connection)
    }

    public var firmwareVersionText: String? {
        guard deviceInfo.firmwareVersion > 0 else { return nil }
        return String(format: "%.2f", Double(deviceInfo.firmwareVersion) / 100.0)
    }

    public var productSummary: String {
        if isBS22 {
            return "BS-22 Speaker Mic"
        }
        if deviceInfo.productID > 0 {
            return "PID \(deviceInfo.productID)"
        }
        return "Unknown accessory"
    }

    public var isBS22: Bool {
        deviceInfo.productID == Self.bs22ProductID
    }

    public var modelName: String {
        if isBS22 {
            return "BS-22 Speaker Mic"
        }
        if deviceInfo.productID > 0 {
            return "Unsupported Mic (PID \(deviceInfo.productID))"
        }
        return "Unsupported Mic"
    }

    public func connect() async throws {
        if isConnected || isConnecting {
            return
        }

        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }

        do {
            try await connection.connect()
            try await hydrate()
            isConnected = true
            lastConnectedAt = Date()
            startBatteryPolling()
        } catch {
            await disconnect()
            errorMessage = error.localizedDescription
            throw error
        }
    }

    public func disconnect() async {
        batteryPollTask?.cancel()
        batteryPollTask = nil
        await connection.disconnect()
        isConnected = false
        isConnecting = false
    }

    public func hydrate() async throws {
        isRefreshing = true
        defer { isRefreshing = false }

        let info = try await connection.getDeviceInfo()
        guard !info.supportsRadio else {
            throw SpeakerMicError.notSpeakerMic
        }

        async let pfTask = connection.getPF()
        async let actionsTask = connection.getPFActionsRaw()
        async let batteryTask = connection.getBatteryLevelAsPercentage()

        let pfConfig = try await pfTask
        let actionsRaw = try await actionsTask
        let battery = (try? await batteryTask) ?? 0

        self.deviceInfo = info
        self.pfConfig = pfConfig
        self.supportedActions = decodeSupportedActions(actionsRaw)
        self.batteryPercent = normalizeBatteryPercent(battery)
        self.errorMessage = nil
    }

    public func refreshBattery() async {
        do {
            let value = try await connection.getBatteryLevelAsPercentage()
            batteryPercent = normalizeBatteryPercent(value)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func updatePF(buttonID: Int, action: PFActionType, effect: PFEffectType) async throws {
        guard let index = pfConfig.pf.firstIndex(where: { $0.buttonID == buttonID && $0.action == action }) else {
            throw SpeakerMicError.missingPFSlot(buttonID: buttonID, action: action)
        }

        var updated = pfConfig.pf
        updated[index] = PF(buttonID: buttonID, action: action, effect: effect)

        isSavingPF = true
        defer { isSavingPF = false }

        let newConfig = PFConfig(pf: updated)
        try await connection.setPF(newConfig)
        try? await Task.sleep(nanoseconds: 200_000_000)
        self.pfConfig = try await connection.getPF()
    }

    private func startBatteryPolling() {
        batteryPollTask?.cancel()
        batteryPollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.batteryPollIntervalNanoseconds)
                guard !Task.isCancelled else { return }
                await self.refreshBattery()
            }
        }
    }

    private func decodeSupportedActions(_ payload: Data) -> [PFEffectType] {
        let reported = payload.map { PFEffectType(rawValue: Int($0)) }
        let merged = Array(Set(reported + [.disable])).sorted { $0.rawValue < $1.rawValue }
        return merged
    }

    private func normalizeBatteryPercent(_ value: Int) -> Int {
        guard (0...100).contains(value) else { return 0 }
        return value
    }
}

public enum SpeakerMicError: LocalizedError {
    case notSpeakerMic
    case missingPFSlot(buttonID: Int, action: PFActionType)

    public var errorDescription: String? {
        switch self {
        case .notSpeakerMic:
            return "This device reports itself as a radio, not the speaker mic accessory."
        case .missingPFSlot(let buttonID, let action):
            return "The speaker mic did not expose a \(action) slot for button \(buttonID)."
        }
    }
}
