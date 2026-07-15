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
    private let stateRestorationEnabled: Bool

    private var restorePendingServiceDiscovery: Bool = false
    private var isDiscoveringServices: Bool = false
    private var connectAttemptStartedAt: Date?
    private var lastConnectedAt: Date?
    private var serviceDiscoveryStartedAt: Date?
    private var characteristicDiscoveryStartedAt: Date?
    
    public weak var radioManager: RadioManager?

    private var canIssueCentralCommands: Bool {
        centralManager.state == .poweredOn
    }

    public var isConnected: Bool {
        peripheral?.state == .connected &&
        writeCharacteristic != nil &&
        indicateCharacteristic != nil
    }

    public init(
        deviceUUID: UUID,
        radioManager: RadioManager? = nil,
        enableStateRestoration: Bool = true
    ) {
        self.deviceUUID = deviceUUID
        self.restoreIdentifier = "com.fieldHT.ble.\(deviceUUID.uuidString)"
        self.stateRestorationEnabled = enableStateRestoration
        self.radioManager = radioManager
        super.init()

        var options: [String: Any] = [
            CBCentralManagerOptionShowPowerAlertKey: true
        ]
        if enableStateRestoration {
            // Restore only the main radio transport. The optional speaker-mic BLE link
            // should stay fully manual so it cannot silently reappear and compete.
            options[CBCentralManagerOptionRestoreIdentifierKey] = restoreIdentifier
        }

        self.centralManager = CBCentralManager(delegate: self, queue: nil, options: options)
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
                self.connectAttemptStartedAt = Date()
                self.lastConnectedAt = nil
                self.serviceDiscoveryStartedAt = nil
                self.characteristicDiscoveryStartedAt = nil
                self.recordCaptureNote(category: "connect_attempt_started", message: "Starting BLE connect attempt", fields: [
                    "device_uuid": self.deviceUUID.uuidString
                ])
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

        if BLECaptureStore.isEnabled {
            Task {
                await BLECaptureStore.shared.recordPacket(
                    direction: "tx",
                    characteristicUUID: writeCharacteristic.uuid.uuidString,
                    data: data
                )
            }
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
        connectAttemptStartedAt = nil
        lastConnectedAt = nil
        serviceDiscoveryStartedAt = nil
        characteristicDiscoveryStartedAt = nil

        peripheral?.delegate = nil
        peripheral = nil
    }

    private func characteristicLabel(_ characteristic: CBCharacteristic) -> String {
        switch characteristic.uuid {
        case radioWriteUUID:
            return "write"
        case radioIndicateUUID:
            return "indicate"
        case radioAuxUUID:
            return "aux"
        default:
            return characteristic.uuid.uuidString
        }
    }

    private func recordCaptureNote(category: String, message: String, fields: [String: String] = [:]) {
        guard BLECaptureStore.isEnabled else { return }
        Task {
            await BLECaptureStore.shared.recordNote(category: category, message: message, fields: fields)
        }
    }

    private func millisecondsSince(_ startedAt: Date?) -> String {
        guard let startedAt else { return "0" }
        return String(Int(Date().timeIntervalSince(startedAt) * 1000.0))
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
                    recordCaptureNote(category: "connect_resume_existing", message: "Reusing existing BLE connection", fields: [
                        "device_uuid": peripheral.identifier.uuidString
                    ])
                    startServiceDiscoveryIfPossible()
                } else {
                    recordCaptureNote(category: "connect_using_retrieved_peripheral", message: "Connecting using retrieved peripheral", fields: [
                        "device_uuid": peripheral.identifier.uuidString
                    ])
                    centralManager.connect(peripheral, options: [
                        CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
                    ])
                }
            } else {
                // Scan for all peripherals since filtering by service UUID may not work reliably.
                recordCaptureNote(category: "connect_scan_started", message: "Scanning for target peripheral", fields: [
                    "device_uuid": deviceUUID.uuidString
                ])
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
        serviceDiscoveryStartedAt = Date()
        recordCaptureNote(category: "service_discovery_started", message: "Starting service discovery", fields: [
            "device_uuid": peripheral.identifier.uuidString
        ])
        peripheral.discoverServices([radioServiceUUID])
    }

    private func startConnectTimeout(seconds: TimeInterval) {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard self.connectContinuation != nil else { return }
            if self.peripheral?.state == .connected || self.didReachReadyState {
                return
            }
            print("BLE: Connect timed out after \(seconds)s")
            self.recordCaptureNote(category: "connect_timeout", message: "BLE connect timed out", fields: ["seconds": String(seconds)])
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
        print("BLE: central state -> \(central.state.rawValue)")
        recordCaptureNote(category: "central_state", message: "Central state updated", fields: ["state": String(central.state.rawValue)])
        switch central.state {
        case .poweredOn:
            beginConnectFlowIfPossible()

            if restorePendingServiceDiscovery {
                startServiceDiscoveryIfPossible()
            }

        case .poweredOff, .unauthorized, .unsupported:
            if connectContinuation != nil {
                failConnect(BLEError.bluetoothUnavailable)
            }

            // Only treat this as a transport drop if we had reached a usable connection.
            if didReachReadyState {
                delegate?.connectionDidDisconnect(self, error: BLEError.bluetoothUnavailable)
                notifyRadioManagerTransportDidDisconnect(error: BLEError.bluetoothUnavailable)
                resetConnectionState()
            }

        case .resetting, .unknown:
            // CoreBluetooth commonly enters these transitional states while creating a
            // new central manager. Keep an in-flight reconnect alive until its state
            // becomes definitive instead of reporting a false Bluetooth failure.
            break

        @unknown default:
            break
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        guard stateRestorationEnabled else { return }
        guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] else {
            return
        }

        if let restored = peripherals.first(where: { $0.identifier == deviceUUID }) {
            print("BLE: Restored peripheral \(restored.identifier.uuidString) state=\(restored.state.rawValue)")
            recordCaptureNote(category: "restore", message: "Restored peripheral", fields: [
                "peripheral": restored.identifier.uuidString,
                "state": String(restored.state.rawValue)
            ])
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

        print("BLE: discovered target peripheral \(peripheral.identifier.uuidString) rssi=\(RSSI)")
        recordCaptureNote(category: "discover", message: "Discovered target peripheral", fields: [
            "peripheral": peripheral.identifier.uuidString,
            "rssi": RSSI.stringValue
        ])
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
        print("BLE: didConnect peripheral \(peripheral.identifier.uuidString)")
        lastConnectedAt = Date()
        recordCaptureNote(category: "connect", message: "Connected peripheral", fields: ["peripheral": peripheral.identifier.uuidString])
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        startServiceDiscoveryIfPossible()
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        print("BLE: didFailToConnect peripheral \(peripheral.identifier.uuidString) error=\(error?.localizedDescription ?? "nil")")
        recordCaptureNote(category: "connect_failed", message: "Failed to connect peripheral", fields: [
            "peripheral": peripheral.identifier.uuidString,
            "error": error?.localizedDescription ?? "nil"
        ])
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

        print(
            "BLE: didDisconnect peripheral \(peripheral.identifier.uuidString) " +
            "requested=\(wasRequested) ready=\(wasReady) " +
            "hadConnect=\(hadConnect) hadDisconnect=\(hadDisconnect) " +
            "error=\(error?.localizedDescription ?? "nil")"
        )
        recordCaptureNote(category: "disconnect", message: "Peripheral disconnected", fields: [
            "peripheral": peripheral.identifier.uuidString,
            "requested": String(wasRequested),
            "ready": String(wasReady),
            "hadConnect": String(hadConnect),
            "hadDisconnect": String(hadDisconnect),
            "error": error?.localizedDescription ?? "nil",
            "connected_ms": millisecondsSince(lastConnectedAt)
        ])

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
            recordCaptureNote(category: "discover_services_error", message: "Service discovery failed", fields: ["error": error.localizedDescription])
            failConnect(error)
            return
        }
        
        guard let services = peripheral.services else {
            print("BLE: No services found")
            failConnect(BLEError.serviceNotFound)
            return
        }
        
        print("BLE: Discovered \(services.count) service(s) for device \(peripheral.identifier.uuidString):")
        recordCaptureNote(category: "services", message: "Discovered services", fields: [
            "peripheral": peripheral.identifier.uuidString,
            "count": String(services.count),
            "uuids": services.map(\.uuid.uuidString).joined(separator: ",")
        ])
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
        characteristicDiscoveryStartedAt = Date()
        recordCaptureNote(category: "radio_service", message: "Found radio service", fields: ["uuid": radioService.uuid.uuidString])
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
            recordCaptureNote(category: "discover_characteristics_error", message: "Characteristic discovery failed", fields: [
                "service": service.uuid.uuidString,
                "error": error.localizedDescription
            ])
            failConnect(error)
            return
        }

        guard let characteristics = service.characteristics else {
            print("BLE: No characteristics found for service \(service.uuid)")
            failConnect(BLEError.characteristicNotFound)
            return
        }
        
        print("BLE: Discovered \(characteristics.count) characteristics for service \(service.uuid):")
        recordCaptureNote(category: "characteristics", message: "Discovered characteristics", fields: [
            "service": service.uuid.uuidString,
            "count": String(characteristics.count),
            "uuids": characteristics.map(\.uuid.uuidString).joined(separator: ",")
        ])
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
            recordCaptureNote(category: "connect_ready", message: "BLE transport ready", fields: [
                "device_uuid": peripheral.identifier.uuidString,
                "total_ms": millisecondsSince(connectAttemptStartedAt),
                "service_ms": millisecondsSince(serviceDiscoveryStartedAt),
                "characteristic_ms": millisecondsSince(characteristicDiscoveryStartedAt)
            ])
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
             print("BLE: Error updating value for char \(characteristicLabel(characteristic)): \(error.localizedDescription)")
             return
        }
        
        guard let data = characteristic.value else { return }

        // During OTA we may receive indications on more than one characteristic.
        guard characteristic.uuid == radioIndicateUUID || characteristic.uuid == radioAuxUUID else { return }

        if BLECaptureStore.isEnabled {
            Task {
                await BLECaptureStore.shared.recordPacket(
                    direction: "rx",
                    characteristicUUID: characteristic.uuid.uuidString,
                    data: data
                )
            }
        }
        
        // print("BLE: Received data: \(data.count) bytes")
        delegate?.connection(self, didReceiveData: data)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        print(
            "BLE: notify state for \(characteristicLabel(characteristic)) " +
            "isNotifying=\(characteristic.isNotifying) " +
            "error=\(error?.localizedDescription ?? "nil")"
        )
        recordCaptureNote(category: "notify_state", message: "Notification state updated", fields: [
            "characteristic": characteristic.uuid.uuidString,
            "label": characteristicLabel(characteristic),
            "isNotifying": String(characteristic.isNotifying),
            "error": error?.localizedDescription ?? "nil"
        ])
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didModifyServices invalidatedServices: [CBService]
    ) {
        let uuids = invalidatedServices.map(\.uuid.uuidString).joined(separator: ",")
        print("BLE: services modified/invalidated -> [\(uuids)]")
        recordCaptureNote(category: "services_modified", message: "Services modified", fields: ["uuids": uuids])
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        print(
            "BLE: didWriteValue for \(characteristicLabel(characteristic)) " +
            "error=\(error?.localizedDescription ?? "nil")"
        )
        recordCaptureNote(category: "write_complete", message: "Characteristic write completed", fields: [
            "characteristic": characteristic.uuid.uuidString,
            "label": characteristicLabel(characteristic),
            "error": error?.localizedDescription ?? "nil"
        ])
    }
}
