import Foundation

// Minimal transport double for exercising BLEConnection without Bluetooth hardware.
public struct CBUUID: Hashable {
    public let uuidString: String
    public init(string: String) { uuidString = string }
}

public enum CBManagerState: Int { case unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn }
public enum CBPeripheralState: Int { case disconnected, connecting, connected, disconnecting }
public enum CBCharacteristicWriteType { case withResponse }

public struct CBCharacteristicProperties: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let notify = Self(rawValue: 1)
    public static let indicate = Self(rawValue: 2)
}

public let CBCentralManagerOptionShowPowerAlertKey = "showPowerAlert"
public let CBCentralManagerOptionRestoreIdentifierKey = "restoreIdentifier"
public let CBConnectPeripheralOptionNotifyOnDisconnectionKey = "notifyOnDisconnection"
public let CBCentralManagerRestoredStatePeripheralsKey = "restoredPeripherals"

@MainActor
public protocol CBCentralManagerDelegate: AnyObject {
    func centralManagerDidUpdateState(_ central: CBCentralManager)
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any])
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber)
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?)
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?)
}

@MainActor
public final class CBCentralManager {
    public static var lastCreated: CBCentralManager?
    public static var retrievedPeripherals: [CBPeripheral] = []
    public static var initialState: CBManagerState = .poweredOn
    public weak var delegate: (any CBCentralManagerDelegate)?
    public var state: CBManagerState
    public private(set) var connectCount = 0
    public private(set) var cancelCount = 0
    public var disconnectImmediately = true

    public init(delegate: any CBCentralManagerDelegate, queue: DispatchQueue?, options: [String: Any]?) {
        self.delegate = delegate
        state = Self.initialState
        Self.lastCreated = self
    }

    public func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [CBPeripheral] {
        Self.retrievedPeripherals.filter { identifiers.contains($0.identifier) }
    }

    public func connect(_ peripheral: CBPeripheral, options: [String: Any]?) {
        connectCount += 1
        peripheral.state = .connecting
    }

    public func cancelPeripheralConnection(_ peripheral: CBPeripheral) {
        cancelCount += 1
        peripheral.state = disconnectImmediately ? .disconnected : .disconnecting
    }

    public func stopScan() {}
    public func scanForPeripherals(withServices services: [CBUUID]?, options: [String: Any]?) {}
}

@MainActor
public protocol CBPeripheralDelegate: AnyObject {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService])
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?)
}

@MainActor
public final class CBPeripheral {
    public let identifier: UUID
    public weak var delegate: (any CBPeripheralDelegate)?
    public var state: CBPeripheralState = .disconnected
    public var services: [CBService]?
    public private(set) var writes: [Data] = []

    public init(identifier: UUID) { self.identifier = identifier }
    public func discoverServices(_ services: [CBUUID]?) {}
    public func discoverCharacteristics(_ characteristics: [CBUUID]?, for service: CBService) {}
    public func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic) {}
    public func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) { writes.append(data) }
}

@MainActor
public final class CBService {
    public let uuid: CBUUID
    public var characteristics: [CBCharacteristic]?
    public init(uuid: CBUUID) { self.uuid = uuid }
}

@MainActor
public final class CBCharacteristic {
    public let uuid: CBUUID
    public var properties: CBCharacteristicProperties
    public var isNotifying = false
    public var value: Data?

    public init(uuid: CBUUID, properties: CBCharacteristicProperties = []) {
        self.uuid = uuid
        self.properties = properties
    }
}
