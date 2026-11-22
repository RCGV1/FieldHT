import Foundation
import CoreBluetooth

let radioServiceUUID = CBUUID(string: "service")
let radioWriteUUID = CBUUID(string: "write")
let radioIndicateUUID = CBUUID(string: "indicate")
let radioAuxUUID = CBUUID(string: "aux")

@MainActor
public final class RadioManager {
    var disconnectCount = 0
    var availableCount = 0
    var unavailableCount = 0
    public func handleTransportDidDisconnect(error: Error?) { disconnectCount += 1 }
    public func handleTransportBluetoothAvailable() { availableCount += 1 }
    public func handleTransportBluetoothUnavailable() { unavailableCount += 1 }
}

actor BLECaptureStore {
    static let isEnabled = false
    static let shared = BLECaptureStore()
    func recordNote(category: String, message: String, fields: [String: String]) {}
    func recordPacket(direction: String, characteristicUUID: String, data: Data) {}
}

@MainActor
private final class ConnectRun {
    var result: Result<Void, Error>?
    var task: Task<Void, Never>?

    init(_ connection: BLEConnection) {
        task = Task {
            do { try await connection.connect(); result = .success(()) }
            catch { result = .failure(error) }
        }
    }
}

@MainActor
private final class Fixture {
    let manager = RadioManager()
    let peripheral = CBPeripheral(identifier: UUID())
    let service = CBService(uuid: radioServiceUUID)
    let write = CBCharacteristic(uuid: radioWriteUUID)
    let indicate = CBCharacteristic(uuid: radioIndicateUUID, properties: .indicate)
    let aux = CBCharacteristic(uuid: radioAuxUUID, properties: .notify)
    let connection: BLEConnection
    let central: CBCentralManager

    init(timeout: TimeInterval = 0.2, startupTimeout: TimeInterval = 0.2, initialState: CBManagerState = .poweredOn) {
        CBCentralManager.retrievedPeripherals = [peripheral]
        CBCentralManager.initialState = initialState
        connection = BLEConnection(deviceUUID: peripheral.identifier, radioManager: manager,
                                   enableStateRestoration: false, connectionTimeout: timeout,
                                   bluetoothStartupTimeout: startupTimeout)
        central = CBCentralManager.lastCreated!
        service.characteristics = [write, indicate, aux]
        peripheral.services = [service]
    }

    func start() async throws -> ConnectRun {
        let expected = central.connectCount + 1
        let run = ConnectRun(connection)
        try await waitUntil { self.central.connectCount == expected }
        return run
    }

    func connectLink() {
        peripheral.state = .connected
        connection.centralManager(central, didConnect: peripheral)
    }

    func discover() {
        connectLink()
        connection.peripheral(peripheral, didDiscoverServices: nil)
        connection.peripheral(peripheral, didDiscoverCharacteristicsFor: service, error: nil)
    }

    func notifications(_ enabled: Bool, characteristic: CBCharacteristic? = nil, error: Error? = nil) {
        let characteristic = characteristic ?? indicate
        characteristic.isNotifying = enabled
        connection.peripheral(peripheral, didUpdateNotificationStateFor: characteristic, error: error)
    }
}

private struct Failure: Error { let message: String }

@MainActor
private func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw Failure(message: message) }
}

@MainActor
private func waitUntil(_ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !predicate() {
        guard ContinuousClock.now < deadline else { throw Failure(message: "Timed out waiting for transport test") }
        try await Task.sleep(for: .milliseconds(1))
    }
}

@MainActor
private func expectSuccess(_ run: ConnectRun) async throws {
    try await waitUntil { run.result != nil }
    guard case .success = run.result else { throw Failure(message: "Expected connection success: \(String(describing: run.result))") }
}

@MainActor
private func expectFailure(_ run: ConnectRun, matching predicate: (Error) -> Bool) async throws {
    try await waitUntil { run.result != nil }
    guard case .failure(let error) = run.result, predicate(error) else {
        throw Failure(message: "Unexpected connection result: \(String(describing: run.result))")
    }
}

@main @MainActor
enum BLEConnectionLifecycleTests {
    static func main() async throws {
        try await waitsForNotifications()
        try await setupTimeouts()
        try await notificationFailures()
        try await invalidatedServices()
        try await cancellationAndRetry()
        try await bluetoothStartupAndRecovery()
        try await disconnectDuringBluetoothChanges()
        try await failedWrites()
        print("BLEConnectionLifecycleTests passed: readiness, setup/startup deadlines, permission errors, Bluetooth recovery, notification loss, service invalidation, cancellation, and disconnect cleanup")
    }

    private static func waitsForNotifications() async throws {
        let f = Fixture()
        let run = try await f.start()
        f.discover()
        try expect(!f.connection.isConnected && run.result == nil, "Characteristic discovery must not complete a connection")
        do {
            try f.connection.send(Data([1]))
            throw Failure(message: "A write was allowed before notifications were ready")
        } catch BLEError.notConnected {}
        f.notifications(true, characteristic: f.aux)
        try expect(!f.connection.isConnected, "Auxiliary notifications must not signal readiness")
        f.notifications(true)
        try await expectSuccess(run)
        try f.connection.send(Data([1]))
        try expect(f.peripheral.writes == [Data([1])], "Ready transport must allow writes")
        try await Task.sleep(for: .milliseconds(250))
        try expect(f.connection.isConnected && f.central.cancelCount == 0, "Cancelled setup deadline must not close a ready link")
        f.notifications(false, characteristic: f.aux, error: BLEError.connectionFailed)
        try expect(f.connection.isConnected && f.manager.disconnectCount == 0, "Optional auxiliary subscription failures must not drop the radio")
    }

    private static func setupTimeouts() async throws {
        for stallDuringNotifications in [false, true] {
            let f = Fixture(timeout: 0.04)
            let run = try await f.start()
            if stallDuringNotifications { f.discover() } else { f.connectLink() }
            try await expectFailure(run) { if case BLEError.connectionTimeout = $0 { return true }; return false }
            try expect(!f.connection.isConnected && f.central.cancelCount == 1, "Stalled setup must cancel the half-open link")
        }
    }

    private static func notificationFailures() async throws {
        let f = Fixture()
        let run = try await f.start()
        f.discover()
        f.notifications(false, error: BLEError.connectionFailed)
        try await expectFailure(run) { if case BLEError.connectionFailed = $0 { return true }; return false }
        try expect(f.manager.disconnectCount == 0, "Failed initial setup must not report a second transport drop")

        let ready = Fixture()
        let readyRun = try await ready.start()
        ready.discover()
        ready.notifications(true)
        try await expectSuccess(readyRun)
        ready.notifications(false)
        try expect(!ready.connection.isConnected && ready.manager.disconnectCount == 1, "Notification loss must trigger reconnect handling")
        ready.connection.centralManager(ready.central, didDisconnectPeripheral: ready.peripheral, error: nil)
        try expect(ready.manager.disconnectCount == 1, "Late disconnect callback must not report the same drop twice")
        ready.notifications(true)
        try expect(!ready.connection.isConnected, "Stale notification callback must not restore readiness")
    }

    private static func invalidatedServices() async throws {
        let f = Fixture()
        let run = try await f.start()
        f.discover()
        f.notifications(true)
        try await expectSuccess(run)
        f.connection.peripheral(f.peripheral, didModifyServices: [CBService(uuid: CBUUID(string: "unrelated"))])
        try expect(f.connection.isConnected, "Unrelated services must not affect the connection")
        f.connection.peripheral(f.peripheral, didModifyServices: [f.service])
        try expect(!f.connection.isConnected && f.manager.disconnectCount == 1, "Invalidated radio service must trigger reconnect handling")
    }

    private static func bluetoothStartupAndRecovery() async throws {
        let pending = Fixture(timeout: 0.02, startupTimeout: 0.3, initialState: .unknown)
        let run = ConnectRun(pending.connection)
        try await Task.sleep(for: .milliseconds(40))
        try expect(run.result == nil && pending.central.connectCount == 0, "Permission startup must have its own deadline and must not issue central commands")
        pending.central.state = .poweredOn
        pending.connection.centralManagerDidUpdateState(pending.central)
        try await waitUntil { pending.central.connectCount == 1 }
        pending.discover()
        pending.notifications(true)
        try await expectSuccess(run)
        try expect(pending.manager.availableCount == 1, "Powered-on transition must wake reconnect handling")
        pending.central.state = .poweredOff
        pending.connection.centralManagerDidUpdateState(pending.central)
        try expect(!pending.connection.isConnected && pending.manager.disconnectCount == 1 && pending.manager.unavailableCount == 1,
                   "Bluetooth turning off must report one recoverable transport drop")
        pending.central.state = .poweredOn
        pending.connection.centralManagerDidUpdateState(pending.central)
        try expect(pending.manager.availableCount == 2, "Bluetooth recovery must wake reconnect handling again")

        for state in [CBManagerState.poweredOff, .unauthorized] {
            let f = Fixture(initialState: state)
            let failure = ConnectRun(f.connection)
            try await expectFailure(failure) { error in
                if state == .poweredOff, case BLEError.bluetoothPoweredOff = error { return true }
                if state == .unauthorized, case BLEError.bluetoothUnauthorized = error { return true }
                return false
            }
            try expect(f.central.connectCount == 0, "Denied or powered-off Bluetooth must not start GATT requests")
        }

        let stalled = Fixture(startupTimeout: 0.02, initialState: .unknown)
        try await expectFailure(ConnectRun(stalled.connection)) { if case BLEError.bluetoothUnavailable = $0 { return true }; return false }
    }

    private static func disconnectDuringBluetoothChanges() async throws {
        for powerOff in [false, true] {
            let f = Fixture()
            let run = try await f.start()
            f.discover()
            f.notifications(true)
            try await expectSuccess(run)
            f.central.disconnectImmediately = false
            var finished = false
            let task = Task { await f.connection.disconnect(); finished = true }
            try await waitUntil { f.central.cancelCount == 1 }
            var secondFinished = false
            let second = Task { await f.connection.disconnect(); secondFinished = true }
            await Task.yield()
            if powerOff {
                f.central.state = .poweredOff
                f.connection.centralManagerDidUpdateState(f.central)
            } else {
                f.notifications(false)
            }
            try await waitUntil { finished && secondFinished }
            await task.value
            await second.value
            try expect(f.central.cancelCount == 1, "Overlapping disconnect callers must share transport cleanup")
            try expect(f.manager.disconnectCount == 0, "Expected disconnects must not restart automatic reconnection")
            try expect(!f.connection.isConnected, "Disconnect cleanup must complete even when Bluetooth or notifications change first")
        }
    }

    private static func failedWrites() async throws {
        let f = Fixture()
        let run = try await f.start()
        f.discover()
        f.notifications(true)
        try await expectSuccess(run)
        f.connection.peripheral(f.peripheral, didWriteValueFor: f.write, error: BLEError.connectionFailed)
        try expect(!f.connection.isConnected && f.manager.disconnectCount == 1,
                   "Failed control writes must invalidate the transport instead of leaving a false connected state")
    }

    private static func cancellationAndRetry() async throws {
        let f = Fixture()
        let cancelled = try await f.start()
        cancelled.task?.cancel()
        try await expectFailure(cancelled) { $0 is CancellationError }
        let retry = try await f.start()
        f.connection.centralManager(f.central, didDisconnectPeripheral: f.peripheral, error: nil)
        try await Task.sleep(for: .milliseconds(10))
        try expect(retry.result == nil, "Cancelled timeout must not terminate a later connection attempt")
        f.discover()
        f.notifications(true)
        try await expectSuccess(retry)

        let neverStarted = Fixture()
        let run = ConnectRun(neverStarted.connection)
        run.task?.cancel()
        try await expectFailure(run) { $0 is CancellationError }
        try expect(neverStarted.central.connectCount == 0, "Already-cancelled tasks must not start a BLE connection")
    }
}
