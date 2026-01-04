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
    case characteristicNotFound

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to device"
        case .bluetoothUnavailable:
            return "Bluetooth is unavailable"
        case .connectionFailed:
            return "Connection failed"
        case .characteristicNotFound:
            return "Required characteristic not found"
        }
    }
}

// MARK: - BLE Connection

public class BLEConnection: NSObject {

    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?

    private var writeCharacteristic: CBCharacteristic?
    private var indicateCharacteristic: CBCharacteristic?

    public weak var delegate: BLEConnectionDelegate?
    private let deviceUUID: UUID

    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var disconnectContinuation: CheckedContinuation<Void, Never>?
    
    public weak var radioManager: RadioManager?

    public var isConnected: Bool {
        peripheral?.state == .connected &&
        writeCharacteristic != nil &&
        indicateCharacteristic != nil
    }

    public init(deviceUUID: UUID, radioManager: RadioManager? = nil) {
        self.deviceUUID = deviceUUID
        self.radioManager = radioManager
        super.init()
    }

    // MARK: - Public API

    public func connect() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.connectContinuation = continuation
            self.centralManager = CBCentralManager(delegate: self, queue: nil)
        }
    }

    public func disconnect() async {
        await withCheckedContinuation { continuation in
            self.disconnectContinuation = continuation
            if let peripheral {
                centralManager?.cancelPeripheralConnection(peripheral)
            } else {
                continuation.resume()
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
        peripheral?.writeValue(data, for: writeCharacteristic, type: .withResponse)
    }
    
    // MARK: - Private Helper
    
    private func resetConnection() {
        print("BLE: Resetting connection state")
        writeCharacteristic = nil
        indicateCharacteristic = nil
        peripheral?.delegate = nil
        peripheral = nil
        centralManager?.delegate = nil
        centralManager = nil
        radioManager?.disconnect()
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEConnection: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            let peripherals = central.retrievePeripherals(withIdentifiers: [deviceUUID])
            if let peripheral = peripherals.first {
                self.peripheral = peripheral
                peripheral.delegate = self
                central.connect(peripheral, options: nil)
            } else {
                // Scan for all peripherals since filtering by service UUID may not work reliably
                central.scanForPeripherals(withServices: nil, options: nil)
            }

        case .poweredOff, .unauthorized, .unsupported, .resetting, .unknown:
            resetConnection()
            delegate?.connectionDidDisconnect(self, error: BLEError.bluetoothUnavailable)

        @unknown default:
            break
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
        central.connect(peripheral, options: nil)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        peripheral.discoverServices([radioServiceUUID])
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        resetConnection()
        connectContinuation?.resume(throwing: error ?? BLEError.connectionFailed)
        connectContinuation = nil
        delegate?.connectionDidDisconnect(self, error: error)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        resetConnection()
        
        disconnectContinuation?.resume()
        disconnectContinuation = nil

        delegate?.connectionDidDisconnect(self, error: error)
    }
}

// MARK: - CBPeripheralDelegate

extension BLEConnection: CBPeripheralDelegate {

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        if let error = error {
            print("BLE: Error discovering services: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else {
            print("BLE: No services found")
            return
        }
        
        print("BLE: Discovered \(services.count) service(s) for device \(peripheral.identifier.uuidString):")
        for service in services {
            print("BLE:   - Service UUID: \(service.uuid.uuidString)")
        }

        for service in services where service.uuid == radioServiceUUID {
            print("BLE: Found radio service UUID: \(service.uuid.uuidString), discovering characteristics...")
            peripheral.discoverCharacteristics(
                [radioWriteUUID, radioIndicateUUID],
                for: service
            )
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            print("BLE: Error discovering characteristics for service \(service.uuid): \(error.localizedDescription)")
            connectContinuation?.resume(throwing: error)
            connectContinuation = nil
            return
        }

        guard let characteristics = service.characteristics else {
            print("BLE: No characteristics found for service \(service.uuid)")
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
            default:
                break
            }
        }

        if writeCharacteristic != nil && indicateCharacteristic != nil {
            print("BLE: All required characteristics found. Connection complete.")
            connectContinuation?.resume()
            connectContinuation = nil
            delegate?.connectionDidConnect(self)
        } else {
             print("BLE: Missing characteristics. Write found: \(writeCharacteristic != nil), Indicate found: \(indicateCharacteristic != nil)")
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
        
        guard
            characteristic.uuid == radioIndicateUUID,
            let data = characteristic.value
        else { return }
        
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
