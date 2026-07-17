import Foundation
import Network
import Combine

public struct APRSIGateConfiguration: Codable, Equatable, Sendable {
    public var isEnabled = false
    public var callsign = ""
    public var passcode = ""
    public var server = "noam.aprs2.net"
    public var radioToInternet = false
    public var internetToRadio = false
    public var receiveMessages = false
    public var receivingRangeKilometers = 200

    public static let servers = [
        "North America": "noam.aprs2.net",
        "South America": "soam.aprs2.net",
        "Europe": "euro.aprs2.net",
        "Asia": "asia.aprs2.net",
        "Australia / New Zealand": "aunz.aprs2.net"
    ]
}

@MainActor
public final class APRSIGateSettingsStore: ObservableObject {
    public static let shared = APRSIGateSettingsStore()

    @Published public var configuration: APRSIGateConfiguration {
        didSet { save() }
    }

    private let defaultsKey = "FieldHT.APRSIGateConfiguration"

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(APRSIGateConfiguration.self, from: data) {
            configuration = saved
        } else {
            configuration = APRSIGateConfiguration()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

@MainActor
public final class APRSIGateService: ObservableObject {
    public static let shared = APRSIGateService()

    @Published public private(set) var status = "Stopped"
    @Published public private(set) var lastError: String?

    private let queue = DispatchQueue(label: "FieldHT.APRSIS")
    private var connection: NWConnection?
    private weak var radioController: RadioController?
    private var removeEventHandler: (() -> Void)?
    private var packetAssembler = TncPacketAssembler()
    private var receiveBuffer = Data()
    private var recentlyHandledPackets: [String: Date] = [:]
    private var radioRateLimiter = APRSRadioRateLimiter.safeDefault
    private var reconnectTask: Task<Void, Never>?
    private var configuration = APRSIGateConfiguration()

    private init() {}

    public func apply(configuration: APRSIGateConfiguration, radioController: RadioController?) {
        self.configuration = configuration
        attach(to: radioController)
        restart()
    }

    public func stop() {
        reconnectTask?.cancel()
        reconnectTask = nil
        connection?.cancel()
        connection = nil
        receiveBuffer.removeAll(keepingCapacity: false)
        status = "Stopped"
    }

    private func attach(to controller: RadioController?) {
        guard radioController !== controller else { return }

        removeEventHandler?()
        removeEventHandler = nil
        radioController = controller
        packetAssembler = TncPacketAssembler()

        guard let controller else { return }
        removeEventHandler = controller.addEventHandler { [weak self] event in
            guard case .tncDataFragmentReceived(let fragment) = event else { return }
            Task { @MainActor [weak self] in
                self?.handleRadioFragment(fragment)
            }
        }
    }

    private func restart() {
        stop()

        guard configuration.isEnabled else { return }
        guard radioController?.isConnected == true else {
            status = "Waiting for radio"
            return
        }
        guard validGatewayCallsign != nil, !configuration.passcode.isEmpty else {
            status = "Needs credentials"
            return
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(configuration.server),
            port: NWEndpoint.Port(rawValue: 14_580)!,
            using: .tcp
        )
        self.connection = connection
        status = "Connecting"
        lastError = nil

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleConnectionState(state, for: connection)
            }
        }
        connection.start(queue: queue)
    }

    private func handleConnectionState(_ state: NWConnection.State, for connection: NWConnection) {
        guard self.connection === connection else { return }

        switch state {
        case .ready:
            status = "Signing in"
            sendLogin()
            receiveNextLine(on: connection)
        case .failed(let error):
            lastError = error.localizedDescription
            status = "Connection failed"
            scheduleReconnect()
        case .waiting(let error):
            lastError = error.localizedDescription
            status = "Waiting for network"
        case .cancelled:
            break
        default:
            break
        }
    }

    private func sendLogin() {
        guard let callsign = validGatewayCallsign else { return }
        let range = min(max(configuration.receivingRangeKilometers, 0), 20_000)
        sendLine("user \(callsign) pass \(configuration.passcode) vers FieldHT 1.0 filter m/\(range)")
    }

    private func receiveNextLine(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.connection === connection else { return }
                if let data {
                    self.receiveBuffer.append(data)
                    self.processReceivedLines()
                }
                if let error {
                    self.lastError = error.localizedDescription
                    self.status = "Connection failed"
                    self.scheduleReconnect()
                } else if isComplete {
                    self.status = "Disconnected"
                    self.scheduleReconnect()
                } else {
                    self.receiveNextLine(on: connection)
                }
            }
        }
    }

    private func processReceivedLines() {
        while let lineEnd = receiveBuffer.firstIndex(of: 0x0A) {
            let lineData = receiveBuffer.prefix(upTo: lineEnd)
            receiveBuffer.removeSubrange(...lineEnd)
            let line = String(decoding: lineData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if line.contains("logresp") && line.contains("verified") {
                status = "Connected"
                continue
            }
            if line.contains("logresp") && line.contains("unverified") {
                lastError = "APRS-IS rejected the callsign or passcode"
                status = "Authentication failed"
                connection?.cancel()
                continue
            }
            forwardInternetPacket(line)
        }
    }

    private func handleRadioFragment(_ fragment: TncDataFragment) {
        guard let rawPacket = packetAssembler.append(fragment),
              configuration.isEnabled,
              configuration.radioToInternet,
              let frame = APRSFrame(ax25Data: rawPacket),
              let line = frame.aprsISLine(gatewayCallsign: configuration.callsign),
              markPacketIfNew(rawPacket)
        else {
            return
        }

        sendLine(line)
    }

    private func forwardInternetPacket(_ line: String) {
        guard configuration.isEnabled,
              configuration.internetToRadio,
              let controller = radioController,
              controller.isConnected,
              let frame = APRSFrame(aprsISLine: line),
              configuration.receiveMessages || !frame.information.hasPrefix(":")
        else {
            return
        }

        let rawPacket = frame.ax25Data
        guard !rawPacket.isEmpty,
              rawPacket.count <= 330,
              markPacketIfNew(rawPacket),
              radioRateLimiter.allowsSend()
        else {
            return
        }

        Task { [weak self, weak controller] in
            guard let self, let controller else { return }
            do {
                try await controller.sendTncData(rawPacket)
            } catch {
                await MainActor.run {
                    self.lastError = "Could not send APRS-IS packet to radio: \(error.localizedDescription)"
                }
            }
        }
    }

    private func sendLine(_ line: String) {
        guard let connection else { return }
        let data = Data((line + "\r\n").utf8)
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                self?.lastError = error.localizedDescription
                self?.status = "Connection failed"
                self?.scheduleReconnect()
            }
        })
    }

    private func scheduleReconnect() {
        guard configuration.isEnabled, reconnectTask == nil else { return }
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            self.reconnectTask = nil
            self.restart()
        }
    }

    private func markPacketIfNew(_ packet: Data) -> Bool {
        let now = Date()
        recentlyHandledPackets = recentlyHandledPackets.filter { now.timeIntervalSince($0.value) < 600 }

        let identifier = packet.base64EncodedString()
        guard recentlyHandledPackets[identifier] == nil else { return false }
        recentlyHandledPackets[identifier] = now
        return true
    }

    private var validGatewayCallsign: String? {
        let candidate = configuration.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let testFrame = APRSFrame(source: candidate, destination: "APRS", information: ">FieldHT")
        return testFrame.ax25Data.isEmpty ? nil : candidate
    }
}
