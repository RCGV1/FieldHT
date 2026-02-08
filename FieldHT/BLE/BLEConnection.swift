import Foundation
import CoreBluetooth

// MARK: - BLE Connection Delegate

public protocol BLEConnectionDelegate: AnyObject {
    func connectionDidConnect(_ connection: BLEConnection)
    func connectionDidDisconnect(_ connection: BLEConnection, error: Error?)
    func connection(_ connection: BLEConnection, didReceiveData data: Data)
}

// MARK: - BLE Errors

public enum BLEError: LocalizedError {
    case notConnected
    case bluetoothUnavailable
    case connectionFailed
    case connectionTimeout
    case serviceNotFound
    case characteristicNotFound

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to device"
        case .bluetoothUnavailable:
            return "Bluetooth is unavailable"
        case .connectionFailed:
            return "Connection failed"
        case .connectionTimeout:
            return "Connection timed out"
        case .serviceNotFound:
            return "Required service not found"
        case .characteristicNotFound:
            return "Required characteristic not found"
        }
    }
}

// MARK: - BLE Connection

@MainActor
public class BLEConnection: NSObject {

    private static let bleCaptureDefaultsKey = "com.fieldHT.debug.bleCapture"

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?

    private var writeCharacteristic: CBCharacteristic?
    private var indicateCharacteristic: CBCharacteristic?
    private var auxCharacteristic: CBCharacteristic?

    public weak var delegate: BLEConnectionDelegate? {
        didSet {
            // State restoration can complete before higher layers attach a delegate.
            if isConnected {
                delegate?.connectionDidConnect(self)
            }
        }
    }
    private let deviceUUID: UUID

    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var disconnectContinuation: CheckedContinuation<Void, Never>?

    private var connectTimeoutTask: Task<Void, Never>?
    private var disconnectTimeoutTask: Task<Void, Never>?
    private var didRequestDisconnect: Bool = false
    private var didReachReadyState: Bool = false
    private let restoreIdentifier: String

    private var restorePendingServiceDiscovery: Bool = false
    private var isDiscoveringServices: Bool = false
    
    public weak var radioManager: RadioManager?

    private var canIssueCentralCommands: Bool {
        centralManager.state == .poweredOn
    }

    public var isConnected: Bool {
        peripheral?.state == .connected &&
        writeCharacteristic != nil &&
        indicateCharacteristic != nil
    }

    public init(deviceUUID: UUID, radioManager: RadioManager? = nil) {
        self.deviceUUID = deviceUUID
        self.restoreIdentifier = "com.fieldHT.ble.\(deviceUUID.uuidString)"
        self.radioManager = radioManager
        super.init()

        // CoreBluetooth requires the delegate to implement state restoration callbacks at init time
        // when a restore identifier is provided.
        self.centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: restoreIdentifier,
                CBCentralManagerOptionShowPowerAlertKey: true
            ]
        )
    }

    // MARK: - Public API

    public func connect() async throws {
        if isConnected {
            return
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Only one connect attempt at a time.
                if self.connectContinuation != nil {
                    self.cancelPendingConnect()
                }

                self.didRequestDisconnect = false
                self.didReachReadyState = false
                self.connectContinuation = continuation
                self.startConnectTimeout(seconds: 20)
                self.beginConnectFlowIfPossible()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelPendingConnect()
            }
        }
    }

    public func disconnect() async {
        // If a connect is in-flight, cancel it first so callers aren't left hanging.
        if connectContinuation != nil {
            cancelPendingConnect()
        }
        await withCheckedContinuation { continuation in
            self.disconnectContinuation = continuation
            self.didRequestDisconnect = true
            self.startDisconnectTimeout(seconds: 5)

            if canIssueCentralCommands {
                centralManager.stopScan()
            }

            if let peripheral = self.peripheral {
                if canIssueCentralCommands {
                    centralManager.cancelPeripheralConnection(peripheral)
                }
                if peripheral.state == .disconnected {
                    // No callback is coming.
                    self.finishDisconnect()
                }
            } else {
                self.finishDisconnect()
            }
        }
    }

    public func send(_ data: Data) throws {
        guard let writeCharacteristic else {
            print("BLE: Attempted to send data but writeCharacteristic is nil")
            throw BLEError.notConnected
        }
        let hex = data.map { String(format: "%02hhx", $0) }.joined()
        print("[BLE-SEND] Writing \(data.count) bytes: \(hex)")

        if UserDefaults.standard.bool(forKey: Self.bleCaptureDefaultsKey) {
            Task { await BLEPacketCapture.shared.record(direction: .tx, characteristic: writeCharacteristic, data: data) }
        }

        peripheral?.writeValue(data, for: writeCharacteristic, type: .withResponse)
    }
    
    // MARK: - Private Helper

    private func resetConnectionState() {
        let shouldLog = (
            connectContinuation != nil ||
            disconnectContinuation != nil ||
            connectTimeoutTask != nil ||
            disconnectTimeoutTask != nil ||
            peripheral != nil ||
            writeCharacteristic != nil ||
            indicateCharacteristic != nil ||
            restorePendingServiceDiscovery ||
            isDiscoveringServices
        )
        if shouldLog {
            print("BLE: Resetting connection state")
        }
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        disconnectTimeoutTask?.cancel()
        disconnectTimeoutTask = nil

        if canIssueCentralCommands {
            centralManager.stopScan()
        }
        writeCharacteristic = nil
        indicateCharacteristic = nil
        auxCharacteristic = nil
        didReachReadyState = false
        didRequestDisconnect = false

        restorePendingServiceDiscovery = false
        isDiscoveringServices = false

        peripheral?.delegate = nil
        peripheral = nil
    }

    private func beginConnectFlowIfPossible() {
        guard connectContinuation != nil else { return }

        switch centralManager.state {
        case .poweredOn:
            let peripherals = centralManager.retrievePeripherals(withIdentifiers: [deviceUUID])
            if let peripheral = peripherals.first {
                self.peripheral = peripheral
                peripheral.delegate = self

                if peripheral.state == .connected {
                    // Common after state restoration or if the system kept the link alive.
                    startServiceDiscoveryIfPossible()
                } else {
                    centralManager.connect(peripheral, options: [
                        CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
                    ])
                }
            } else {
                // Scan for all peripherals since filtering by service UUID may not work reliably.
                centralManager.scanForPeripherals(withServices: nil, options: nil)
            }

        case .unknown, .resetting:
            // Wait for a definitive state; CoreBluetooth often starts as .unknown.
            return

        case .poweredOff, .unauthorized, .unsupported:
            failConnect(BLEError.bluetoothUnavailable)

        @unknown default:
            break
        }
    }

    private func startServiceDiscoveryIfPossible() {
        // Calling service discovery before the central is powered on produces
        // "API MISUSE" logs and can behave unpredictably.
        guard centralManager.state == .poweredOn else { return }
        guard let peripheral else { return }
        guard peripheral.state == .connected else { return }

        if isConnected {
            restorePendingServiceDiscovery = false
            return
        }

        if isDiscoveringServices {
            return
        }

        isDiscoveringServices = true
        restorePendingServiceDiscovery = false
        peripheral.discoverServices([radioServiceUUID])
    }

    private func startConnectTimeout(seconds: TimeInterval) {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard self.connectContinuation != nil else { return }
            print("BLE: Connect timed out after \(seconds)s")
            if self.canIssueCentralCommands {
                self.centralManager.stopScan()
                if let peripheral = self.peripheral {
                    self.centralManager.cancelPeripheralConnection(peripheral)
                }
            }
            self.failConnect(BLEError.connectionTimeout)
        }
    }

    private func startDisconnectTimeout(seconds: TimeInterval) {
        disconnectTimeoutTask?.cancel()
        disconnectTimeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard self.disconnectContinuation != nil else { return }
            print("BLE: Disconnect timed out after \(seconds)s")
            self.finishDisconnect()
        }
    }

    private func cancelPendingConnect() {
        guard connectContinuation != nil else { return }
        if canIssueCentralCommands {
            centralManager.stopScan()
            if let peripheral {
                centralManager.cancelPeripheralConnection(peripheral)
            }
        }
        failConnect(CancellationError())
    }

    private func failConnect(_ error: Error) {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil

        let continuation = connectContinuation
        connectContinuation = nil
        resetConnectionState()
        continuation?.resume(throwing: error)
    }

    private func finishDisconnect() {
        disconnectTimeoutTask?.cancel()
        disconnectTimeoutTask = nil

        let continuation = disconnectContinuation
        disconnectContinuation = nil
        resetConnectionState()
        continuation?.resume()
    }

    private func notifyRadioManagerTransportDidDisconnect(error: Error?) {
        guard let radioManager else { return }
        radioManager.handleTransportDidDisconnect(error: error)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEConnection: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            beginConnectFlowIfPossible()

            if restorePendingServiceDiscovery {
                startServiceDiscoveryIfPossible()
            }

        case .poweredOff, .unauthorized, .unsupported, .resetting, .unknown:
            if connectContinuation != nil {
                failConnect(BLEError.bluetoothUnavailable)
            }

            // Only treat this as a transport drop if we had reached a usable connection.
            if didReachReadyState {
                delegate?.connectionDidDisconnect(self, error: BLEError.bluetoothUnavailable)
                notifyRadioManagerTransportDidDisconnect(error: BLEError.bluetoothUnavailable)
                resetConnectionState()
            }

        @unknown default:
            break
        }
    }

    @objc public func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] else {
            return
        }

        if let restored = peripherals.first(where: { $0.identifier == deviceUUID }) {
            print("BLE: Restored peripheral \(restored.identifier.uuidString) state=\(restored.state.rawValue)")
            self.peripheral = restored
            restored.delegate = self

            // If we're already connected, move straight to service discovery.
            if restored.state == .connected {
                restorePendingServiceDiscovery = true
                startServiceDiscoveryIfPossible()
            }
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard peripheral.identifier == deviceUUID else { return }

        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
    }

    public func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        startServiceDiscoveryIfPossible()
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        failConnect(error ?? BLEError.connectionFailed)
        delegate?.connectionDidDisconnect(self, error: error)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let wasRequested = didRequestDisconnect
        let wasReady = didReachReadyState

        let hadConnect = connectContinuation != nil
        let hadDisconnect = disconnectContinuation != nil

        if hadConnect {
            failConnect(error ?? BLEError.connectionFailed)
        }

        if hadDisconnect {
            finishDisconnect()
        }

        if !hadConnect && !hadDisconnect {
            resetConnectionState()
        }

        delegate?.connectionDidDisconnect(self, error: error)

        if wasReady && !wasRequested {
            notifyRadioManagerTransportDidDisconnect(error: error)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEConnection: CBPeripheralDelegate {

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        isDiscoveringServices = false
        if let error = error {
            print("BLE: Error discovering services: \(error.localizedDescription)")
            failConnect(error)
            return
        }
        
        guard let services = peripheral.services else {
            print("BLE: No services found")
            failConnect(BLEError.serviceNotFound)
            return
        }
        
        print("BLE: Discovered \(services.count) service(s) for device \(peripheral.identifier.uuidString):")
        for service in services {
            print("BLE:   - Service UUID: \(service.uuid.uuidString)")
        }

        let radioService = services.first(where: { $0.uuid == radioServiceUUID })
        guard let radioService else {
            print("BLE: Radio service UUID not found on device")
            failConnect(BLEError.serviceNotFound)
            return
        }

        print("BLE: Found radio service UUID: \(radioService.uuid.uuidString), discovering characteristics...")
        peripheral.discoverCharacteristics(
            [radioWriteUUID, radioIndicateUUID, radioAuxUUID],
            for: radioService
        )
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            print("BLE: Error discovering characteristics for service \(service.uuid): \(error.localizedDescription)")
            failConnect(error)
            return
        }

        guard let characteristics = service.characteristics else {
            print("BLE: No characteristics found for service \(service.uuid)")
            failConnect(BLEError.characteristicNotFound)
            return
        }
        
        print("BLE: Discovered \(characteristics.count) characteristics for service \(service.uuid):")
        for char in characteristics {
            print("BLE:   - Char UUID: \(char.uuid) (Props: \(char.properties.rawValue))")
        }

        for characteristic in characteristics {
            switch characteristic.uuid {
            case radioWriteUUID:
                print("BLE: Found Write Characteristic")
                writeCharacteristic = characteristic
            case radioIndicateUUID:
                print("BLE: Found Indicate Characteristic")
                indicateCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            case radioAuxUUID:
                // The official app appears to know about this characteristic. Subscribe if it supports indications/notifications.
                auxCharacteristic = characteristic
                if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                    print("BLE: Found Aux Characteristic (subscribing)")
                    peripheral.setNotifyValue(true, for: characteristic)
                } else {
                    print("BLE: Found Aux Characteristic (no notify/indicate)")
                }
            default:
                break
            }
        }

        if writeCharacteristic != nil && indicateCharacteristic != nil {
            print("BLE: All required characteristics found. Connection complete.")
            connectTimeoutTask?.cancel()
            connectTimeoutTask = nil
            didReachReadyState = true

            if let continuation = connectContinuation {
                connectContinuation = nil
                continuation.resume()
            }
            delegate?.connectionDidConnect(self)
        } else {
             print("BLE: Missing characteristics. Write found: \(writeCharacteristic != nil), Indicate found: \(indicateCharacteristic != nil)")
             failConnect(BLEError.characteristicNotFound)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
             print("BLE: Error updating value for char \(characteristic.uuid): \(error.localizedDescription)")
             return
        }
        
        guard let data = characteristic.value else { return }

        // During OTA we may receive indications on more than one characteristic.
        guard characteristic.uuid == radioIndicateUUID || characteristic.uuid == radioAuxUUID else { return }

        if UserDefaults.standard.bool(forKey: Self.bleCaptureDefaultsKey) {
            Task { await BLEPacketCapture.shared.record(direction: .rx, characteristic: characteristic, data: data) }
        }
        
        // print("BLE: Received data: \(data.count) bytes")
        delegate?.connection(self, didReceiveData: data)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        // Optional: handle write confirmation
    }
}

// MARK: - Debug Packet Capture (JSONL)

private actor BLEPacketCapture {
    enum Direction: String {
        case tx
        case rx
    }

    static let shared = BLEPacketCapture()

    private let maxBytes: Int = 5 * 1024 * 1024
    private let fileName: String = "fieldht_ble_capture.jsonl"
    private var didLogLocation: Bool = false

    private func logURL() -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return caches.appendingPathComponent(fileName, isDirectory: false)
    }

    private func rotateIfNeeded(at url: URL) {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber
        else { return }

        if size.intValue < maxBytes { return }

        let rotated = url.deletingLastPathComponent().appendingPathComponent("\(fileName).1", isDirectory: false)
        _ = try? fm.removeItem(at: rotated)
        _ = try? fm.moveItem(at: url, to: rotated)
    }

    func record(direction: Direction, characteristic: CBCharacteristic?, data: Data) {
        guard let url = logURL() else { return }
        let fm = FileManager.default

        if !didLogLocation {
            didLogLocation = true
            print("[BLE-CAPTURE] Writing JSONL to: \(url.path)")
            print("[BLE-CAPTURE] Rotate at ~\(maxBytes) bytes")
        }

        if !fm.fileExists(atPath: url.path) {
            _ = fm.createFile(atPath: url.path, contents: nil)
        } else {
            rotateIfNeeded(at: url)
        }

        let uuid = characteristic?.uuid.uuidString.lowercased() ?? ""
        let ms = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        let hex = data.map { String(format: "%02hhx", $0) }.joined()

        // JSONL for easy grepping/parsing.
        let line = "{\"unix_ms\":\(ms),\"dir\":\"\(direction.rawValue)\",\"uuid\":\"\(uuid)\",\"len\":\(data.count),\"hex\":\"\(hex)\"}\n"
        guard let lineData = line.data(using: .utf8) else { return }

        do {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: lineData)
            try handle.close()
        } catch {
            // Best-effort only.
        }
    }
}
