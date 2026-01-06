import Foundation
import CoreBluetooth
import Combine

// MARK: - Radio Service UUID
// Replace with your actual radio service UUID
// Based on your logs: 00001100-D102-11E1-9B23-00025B00A5A5

// MARK: - Discovered Device
public struct DiscoveredDevice: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let rssi: Int
    public let peripheral: CBPeripheral
    public var hasRadioService: Bool?
    public let isPaired: Bool

    public init(
        peripheral: CBPeripheral,
        rssi: Int,
        hasRadioService: Bool? = nil,
        isPaired: Bool = false
    ) {
        self.id = peripheral.identifier
        self.name = peripheral.name ?? "Unknown Device"
        self.rssi = rssi
        self.peripheral = peripheral
        self.hasRadioService = hasRadioService
        self.isPaired = isPaired
    }

    public static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - BLE Scanner
@MainActor
public final class BLEScanner: NSObject, ObservableObject {

    // Published
    @Published public var discoveredDevices: [DiscoveredDevice] = []
    @Published public var isScanning: Bool = false
    @Published public var bluetoothState: CBManagerState = .unknown
    @Published public var statusMessage: String = ""

    // Private
    private var centralManager: CBCentralManager!
    private var devices: [UUID: DiscoveredDevice] = [:]
    private var validationCompletions: [UUID: (Bool) -> Void] = [:]
    private var validationTimeouts: [UUID: Timer] = [:]
    
    // UserDefaults key for storing last paired device
    private let lastPairedDeviceKey = "com.fieldHT.lastPairedDeviceUUID"

    // MARK: - Init
    public override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Last Paired Device Management
    public var lastPairedDeviceUUID: UUID? {
        get {
            guard let uuidString = UserDefaults.standard.string(forKey: lastPairedDeviceKey),
                  let uuid = UUID(uuidString: uuidString) else {
                return nil
            }
            return uuid
        }
        set {
            if let uuid = newValue {
                UserDefaults.standard.set(uuid.uuidString, forKey: lastPairedDeviceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastPairedDeviceKey)
            }
        }
    }
    
    public func clearLastPairedDevice() {
        discoveredDevices.removeAll { $0.id == lastPairedDeviceUUID }
        lastPairedDeviceUUID = nil
        statusMessage = "Cleared last paired device"
    }
    
    public func saveLastPairedDevice(_ device: DiscoveredDevice) {
        lastPairedDeviceUUID = device.id
        statusMessage = "Saved \(device.name) as last paired device"
    }

    // MARK: - Scanning
    public func startScanning() {
        guard centralManager.state == .poweredOn else {
            statusMessage = "Bluetooth is not powered on"
            return
        }
        guard !isScanning else { return }

        devices.removeAll()
        discoveredDevices.removeAll()

        isScanning = true
        statusMessage = "Scanning for devices..."
        
        // First, check for previously paired device
        checkForPreviouslyPairedDevice()

        // Then scan for new devices with the radio pairing service
        centralManager.scanForPeripherals(
            withServices: [radioPairingUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
    
    private func checkForPreviouslyPairedDevice() {
        // Check if we have a previously paired device
        guard let lastUUID = lastPairedDeviceUUID else { return }
        
        // Try to retrieve the peripheral by UUID
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [lastUUID])
        
        guard let peripheral = peripherals.first else {
            // Device not found, clear it
            clearLastPairedDevice()
            return
        }
        
        // Found the peripheral, add it to the list
        let device = DiscoveredDevice(
            peripheral: peripheral,
            rssi: -60, // Default RSSI for known devices
            hasRadioService: nil,
            isPaired: true
        )
        devices[peripheral.identifier] = device
        updateDiscoveredDevices()
        
        statusMessage = "Found previously paired device: \(peripheral.name ?? "Unknown")"
    }

    public func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        statusMessage = "Scanning stopped"
        
        // Cancel any pending validations
        for (id, timer) in validationTimeouts {
            timer.invalidate()
            validationCompletions[id]?(false)
        }
        validationTimeouts.removeAll()
        validationCompletions.removeAll()
    }

    // MARK: - Connection Validation
    public func validateRadioService(
        _ device: DiscoveredDevice,
        completion: @escaping (Bool) -> Void
    ) {
        let peripheral = device.peripheral

        // If already validated, return immediately
        if let hasRadio = device.hasRadioService {
            completion(hasRadio)
            return
        }

        // If already validating, queue the completion
        if validationCompletions[peripheral.identifier] != nil {
            let existingCompletion = validationCompletions[peripheral.identifier]
            validationCompletions[peripheral.identifier] = { result in
                existingCompletion?(result)
                completion(result)
            }
            return
        }

        peripheral.delegate = self
        validationCompletions[peripheral.identifier] = completion

        // Set a timeout for validation
        let timeout = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleValidationTimeout(for: peripheral)
            }
        }
        validationTimeouts[peripheral.identifier] = timeout

        // Connect if not already connected
        if peripheral.state != .connected {
            statusMessage = "Connecting to \(device.name)..."
            centralManager.connect(peripheral, options: nil)
        } else {
            // Already connected, just discover services
            peripheral.discoverServices(nil) // Discover all services for paired devices
        }
    }

    private func handleValidationTimeout(for peripheral: CBPeripheral) {
        validationTimeouts[peripheral.identifier]?.invalidate()
        validationTimeouts[peripheral.identifier] = nil
        
        validationCompletions[peripheral.identifier]?(false)
        validationCompletions[peripheral.identifier] = nil
        
        if peripheral.state == .connected {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        
        statusMessage = "Validation timeout for \(peripheral.name ?? "device")"
    }

    private func updateDiscoveredDevices() {
        // Sort: paired first (with star), then by RSSI
        discoveredDevices = devices.values.sorted { device1, device2 in
            if device1.isPaired != device2.isPaired {
                return device1.isPaired
            }
            return device1.rssi > device2.rssi
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEScanner: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state

        switch central.state {
        case .poweredOn:
            statusMessage = "Bluetooth is ready"
        case .poweredOff:
            statusMessage = "Bluetooth is powered off"
            stopScanning()
            devices.removeAll()
            discoveredDevices.removeAll()
        case .unauthorized:
            statusMessage = "Bluetooth access not authorized"
        case .unsupported:
            statusMessage = "Bluetooth not supported"
        case .resetting:
            statusMessage = "Bluetooth is resetting"
        case .unknown:
            statusMessage = "Bluetooth state unknown"
        @unknown default:
            statusMessage = "Unknown bluetooth state"
        }

        if central.state != .poweredOn {
            stopScanning()
            devices.removeAll()
            discoveredDevices.removeAll()
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // Skip if RSSI is invalid
        guard RSSI.intValue != 127 else { return }

        // Check if device already exists
        if var existingDevice = devices[peripheral.identifier] {
            // Update RSSI if it's a new scan
            existingDevice = DiscoveredDevice(
                peripheral: peripheral,
                rssi: RSSI.intValue,
                hasRadioService: existingDevice.hasRadioService,
                isPaired: existingDevice.isPaired
            )
            devices[peripheral.identifier] = existingDevice
        } else {
            // New device discovered
            let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
            let hasRadioInAdvertisement = advertisedServices?.contains(radioPairingUUID) ?? false

            let device = DiscoveredDevice(
                peripheral: peripheral,
                rssi: RSSI.intValue,
                hasRadioService: hasRadioInAdvertisement ? true : nil,
                isPaired: false
            )
            devices[peripheral.identifier] = device
        }

        updateDiscoveredDevices()
    }

    public func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        statusMessage = "Connected to \(peripheral.name ?? "device")"
        // Discover all services for validation
        peripheral.discoverServices(nil)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        statusMessage = "Failed to connect: \(error?.localizedDescription ?? "unknown error")"
        
        validationTimeouts[peripheral.identifier]?.invalidate()
        validationTimeouts[peripheral.identifier] = nil
        
        validationCompletions[peripheral.identifier]?(false)
        validationCompletions[peripheral.identifier] = nil
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        if let error = error {
            statusMessage = "Disconnected: \(error.localizedDescription)"
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BLEScanner: CBPeripheralDelegate {

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        // Clear timeout
        validationTimeouts[peripheral.identifier]?.invalidate()
        validationTimeouts[peripheral.identifier] = nil

        if let error = error {
            statusMessage = "Service discovery error: \(error.localizedDescription)"
            validationCompletions[peripheral.identifier]?(false)
            validationCompletions[peripheral.identifier] = nil
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        // Check if device has the radio service UUID
        let hasRadio = peripheral.services?.contains(where: {
            $0.uuid == radioPairingUUID || $0.uuid == radioServiceUUID
        }) == true

        // Update device entry
        if var device = devices[peripheral.identifier] {
            device = DiscoveredDevice(
                peripheral: peripheral,
                rssi: device.rssi,
                hasRadioService: hasRadio,
                isPaired: device.isPaired
            )
            devices[peripheral.identifier] = device
            updateDiscoveredDevices()
        }

        // Finish validation
        validationCompletions[peripheral.identifier]?(hasRadio)
        validationCompletions[peripheral.identifier] = nil

        // Disconnect non-radio devices immediately
        if !hasRadio {
            statusMessage = "\(peripheral.name ?? "Device") does not have radio service"
            centralManager.cancelPeripheralConnection(peripheral)
        } else {
            statusMessage = "\(peripheral.name ?? "Device") has radio service!"
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        // Optional: Handle characteristic discovery if needed
    }
}
