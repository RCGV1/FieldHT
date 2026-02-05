#!/usr/bin/env swift

import CoreBluetooth
import Dispatch
import Foundation

// UV-PRO CoreBluetooth region-name tester
// This follows the same connection pattern as FieldHT iOS:
// scan (no service filter) -> connect -> discover radio service -> discover write/indicate chars -> enable notify.

// Known UV-PRO service/characteristic UUIDs (may vary by firmware)
// Expected radio service: 00001100-D102-11E1-9B23-00025B00A5A5
// Some firmware versions use: 00000001-BA2A-46C9-AE49-01B0961F68BB

private let radioServiceUUID = CBUUID(string: "00001100-D102-11E1-9B23-00025B00A5A5")
private let radioWriteUUID = CBUUID(string: "00001101-D102-11E1-9B23-00025B00A5A5")
private let radioIndicateUUID = CBUUID(string: "00001102-D102-11E1-9B23-00025B00A5A5")
// FieldHT scans for this pairing service UUID when discovering radios.
private let radioPairingUUID = CBUUID(string: "88A1")

private struct ProtoMsg {
    let group: UInt16
    let isReply: Bool
    let command: UInt16
    let body: Data
}

private enum CliError: Error, CustomStringConvertible {
    case bluetoothUnavailable
    case scanTimeout
    case connectTimeout
    case missingCharacteristics
    case disconnected(String?)
    case timeout(String)
    case badReply(String)
    case badArgs(String)

    var description: String {
        switch self {
        case .bluetoothUnavailable: return "Bluetooth unavailable"
        case .scanTimeout: return "Scan timed out"
        case .connectTimeout: return "Connect timed out"
        case .missingCharacteristics: return "Missing required characteristics"
        case .disconnected(let s): return "Disconnected" + (s.map { ": \($0)" } ?? "")
        case .timeout(let s): return "Timeout: \(s)"
        case .badReply(let s): return "Bad reply: \(s)"
        case .badArgs(let s): return "Bad args: \(s)"
        }
    }
}

private func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

private struct DiscoveredInfo {
    let uuid: UUID
    let name: String
    let rssi: Int
    let isConnectable: Bool?
    let localName: String?
    let serviceUUIDs: [CBUUID]
    let mfgLen: Int?
}

private func encodeMessage(group: UInt16, command: UInt16, body: Data, isReply: Bool = false) -> Data {
    var d = Data()
    d.append(UInt8(group >> 8))
    d.append(UInt8(group & 0xFF))
    let cmdField: UInt16 = (command & 0x7FFF) | (isReply ? 0x8000 : 0)
    d.append(UInt8(cmdField >> 8))
    d.append(UInt8(cmdField & 0xFF))
    d.append(body)
    return d
}

private func decodeMessage(_ data: Data) throws -> ProtoMsg {
    guard data.count >= 4 else { throw CliError.badReply("too short (\(data.count))") }
    let group = (UInt16(data[0]) << 8) | UInt16(data[1])
    let cmdField = (UInt16(data[2]) << 8) | UInt16(data[3])
    let isReply = (cmdField & 0x8000) != 0
    let cmd = cmdField & 0x7FFF
    return ProtoMsg(group: group, isReply: isReply, command: cmd, body: data.subdata(in: 4..<data.count))
}

private func encodeName10(_ s: String) -> Data {
    let b = Array(s.utf8)
    let cut = Array(b.prefix(10))
    var out = Data(cut)
    if out.count < 10 { out.append(Data(repeating: 0, count: 10 - out.count)) }
    return out
}

@MainActor
private final class UVProCB: NSObject {
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var indicateChar: CBCharacteristic?

    private var verbose: Bool = false
    private var nameContains: String?
    private var targetUUID: UUID?
    private var listOnly: Bool = false
    private var requirePairingService: Bool = false
    private var discoverAllServices: Bool = false
    private var advertisedServiceUUID: CBUUID?

    private var listContinuation: CheckedContinuation<Void, Error>?
    private var connectContinuation: CheckedContinuation<Void, Error>?

    private var scanStopTask: Task<Void, Never>?
    private var connectStopTask: Task<Void, Never>?

    private enum Phase: String {
        case idle
        case scanning
        case connecting
        case discoveringServices
        case discoveringChars
        case ready
    }
    private var phase: Phase = .idle

    private var serviceDiscoveryDelayMs: Int = 0

    private var scanTimeoutS: Double = 0
    private var connectTimeoutS: Double = 0
    private var allowDuplicates: Bool = false

    private var requestedNotify: Bool = false
    private var notifyReady: Bool = false

    private var pending: [UInt32: CheckedContinuation<ProtoMsg, Error>] = [:]
    private var didDiscover: [UUID: DiscoveredInfo] = [:]

    func connect(
        nameContains: String?,
        targetUUID: UUID?,
        scanTimeoutS: Double,
        connectTimeoutS: Double,
        listOnly: Bool,
        requirePairingService: Bool,
        discoverAllServices: Bool,
        verbose: Bool
    ) async throws {
        self.verbose = verbose
        self.nameContains = nameContains
        self.targetUUID = targetUUID
        self.listOnly = listOnly
        self.requirePairingService = requirePairingService
        self.discoverAllServices = discoverAllServices
        self.phase = .idle
        self.scanTimeoutS = scanTimeoutS
        self.connectTimeoutS = connectTimeoutS
        self.allowDuplicates = false

        self.requestedNotify = false
        self.notifyReady = false

        scanStopTask?.cancel()
        connectStopTask?.cancel()

        central = CBCentralManager(delegate: self, queue: nil)

        if listOnly {
            scanStopTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(scanTimeoutS * 1_000_000_000))
                self.central.stopScan()
                self.listContinuation?.resume()
                self.listContinuation = nil
            }
            try await withTimeout(seconds: scanTimeoutS + 2.0, label: "scan") {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    self.listContinuation = cont
                }
            }
            return
        }

        connectStopTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(connectTimeoutS * 1_000_000_000))
            if self.connectContinuation != nil {
                self.central.stopScan()
                self.connectContinuation?.resume(throwing: CliError.connectTimeout)
                self.connectContinuation = nil
            }
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.connectContinuation = cont
        }
    }

    func disconnect() {
        scanStopTask?.cancel()
        scanStopTask = nil
        connectStopTask?.cancel()
        connectStopTask = nil
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }
    }

    func setServiceDiscoveryDelayMs(_ ms: Int) {
        self.serviceDiscoveryDelayMs = max(0, ms)
    }

    func setDiscoverAllServices(_ enabled: Bool) {
        self.discoverAllServices = enabled
    }

    func listDiscovered() {
        let items = didDiscover.values.sorted { $0.rssi > $1.rssi }
        if items.isEmpty {
            print("No devices discovered.")
            return
        }
        print("Discovered \(items.count) device(s):")
        for (i, it) in items.enumerated() {
            let svcStr = it.serviceUUIDs.map { $0.uuidString }.joined(separator: ",")
            var extras: [String] = []
            if let c = it.isConnectable { extras.append("connectable=\(c ? 1 : 0)") }
            if let ln = it.localName, ln != it.name { extras.append("local='\(ln)'") }
            if let ml = it.mfgLen { extras.append("mfg=\(ml)b") }
            if !svcStr.isEmpty { extras.append("svc=[\(svcStr)]") }
            let extraStr = extras.isEmpty ? "" : "  " + extras.joined(separator: " ")
            print("  [\(i)] \(it.name)  uuid=\(it.uuid.uuidString) rssi=\(it.rssi)\(extraStr)")
        }
    }

    func sendAndWait(group: UInt16, command: UInt16, body: Data, timeoutS: Double) async throws -> ProtoMsg {
        guard let p = peripheral, let w = writeChar else { throw CliError.disconnected("not connected") }
        let frame = encodeMessage(group: group, command: command, body: body, isReply: false)
        let key: UInt32 = (UInt32(group) << 16) | UInt32(command)

        if verbose {
            print("[BLE-TX] grp=\(group) cmd=\(command) body=\(hex(body))")
            print("[BLE-TX-RAW] \(hex(frame))")
        }

        return try await withTimeout(seconds: timeoutS, label: "reply grp=\(group) cmd=\(command)") {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ProtoMsg, Error>) in
                self.pending[key] = cont
                p.writeValue(frame, for: w, type: .withResponse)
            }
        }
    }
}

extension UVProCB: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                if self.listOnly {
                    if self.verbose { print("[BLE] poweredOn; scanning (no service filter)") }
                    self.phase = .scanning
                    central.scanForPeripherals(
                        withServices: nil,
                        options: [CBCentralManagerScanOptionAllowDuplicatesKey: self.allowDuplicates]
                    )
                    return
                }

                if let target = self.targetUUID {
                    let peripherals = central.retrievePeripherals(withIdentifiers: [target])
                    if let p = peripherals.first {
                        if self.verbose {
                            print("[BLE] retrievePeripherals hit uuid=\(target.uuidString) name=\(p.name ?? "(no name)")")
                        }
                        self.phase = .connecting
                        self.peripheral = p
                        p.delegate = self
                        // Since we don't have advertisement data from retrievePeripherals,
                        // discover all services to find the UV-PRO's actual service UUID
                        self.discoverAllServices = true
                        let options: [String: Any] = [
                            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
                        ]
                        central.connect(p, options: options)
                        return
                    }
                }

                if self.verbose { print("[BLE] poweredOn; scanning (no service filter)") }
                self.phase = .scanning
                central.scanForPeripherals(
                    withServices: nil,
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: self.allowDuplicates]
                )

                scanStopTask?.cancel()
                scanStopTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(self.scanTimeoutS * 1_000_000_000))
                    if self.phase == .scanning {
                        self.central.stopScan()
                        self.connectContinuation?.resume(throwing: CliError.scanTimeout)
                        self.connectContinuation = nil
                    }
                }
            case .poweredOff, .unauthorized, .unsupported, .resetting, .unknown:
                self.listContinuation?.resume(throwing: CliError.bluetoothUnavailable)
                self.listContinuation = nil
                self.connectContinuation?.resume(throwing: CliError.bluetoothUnavailable)
                self.connectContinuation = nil
            @unknown default:
                self.listContinuation?.resume(throwing: CliError.bluetoothUnavailable)
                self.listContinuation = nil
                self.connectContinuation?.resume(throwing: CliError.bluetoothUnavailable)
                self.connectContinuation = nil
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            let name = peripheral.name ?? "(no name)"

            let svc = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
            let hasPairing = svc.contains(radioPairingUUID)
            let hasRadioSvc = svc.contains(radioServiceUUID)

            // Capture the advertised service UUID for this peripheral if it's not the expected one
            if let firstSvc = svc.first {
                self.advertisedServiceUUID = firstSvc
            }

            self.didDiscover[peripheral.identifier] = DiscoveredInfo(
                uuid: peripheral.identifier,
                name: name,
                rssi: RSSI.intValue,
                isConnectable: (advertisementData["kCBAdvDataIsConnectable"] as? NSNumber)?.boolValue,
                localName: advertisementData[CBAdvertisementDataLocalNameKey] as? String,
                serviceUUIDs: svc,
                mfgLen: (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?.count
            )

            if self.verbose {
                let svcStr = svc.map { $0.uuidString }.joined(separator: ",")
                var extra: [String] = []
                if let isConn = (advertisementData["kCBAdvDataIsConnectable"] as? NSNumber)?.boolValue {
                    extra.append("connectable=\(isConn)")
                }
                if let local = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
                    extra.append("local='\(local)'")
                }
                if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
                    extra.append("mfg=\(mfg.count)b")
                }
                if !svcStr.isEmpty { extra.append("svc=[\(svcStr)]") }
                if !extra.isEmpty {
                    print("[BLE] adv: \(name) uuid=\(peripheral.identifier.uuidString) rssi=\(RSSI) \(extra.joined(separator: " "))")
                }
            }

            if self.listOnly {
                return
            }

            if self.phase != .scanning { return }

            if self.requirePairingService, !hasPairing {
                if !hasRadioSvc { return }
            }

            if let target = self.targetUUID {
                if peripheral.identifier != target { return }
            } else {
                if let nc = self.nameContains, !nc.isEmpty {
                    if name.range(of: nc, options: .caseInsensitive) == nil {
                        if !(hasPairing || hasRadioSvc) { return }
                    }
                }
            }

            if self.verbose {
                print(
                    "[BLE] matched device: \(name) uuid=\(peripheral.identifier.uuidString) rssi=\(RSSI) pairingSvc=\(hasPairing ? 1 : 0) radioSvc=\(hasRadioSvc ? 1 : 0)"
                )
            }
            central.stopScan()
            self.phase = .connecting
            self.peripheral = peripheral
            peripheral.delegate = self
            let options: [String: Any] = [
                CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
            ]
            central.connect(peripheral, options: options)
            self.listContinuation?.resume()
            self.listContinuation = nil
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            if self.verbose { print("[BLE] connected; discovering radio service") }
            self.phase = .discoveringServices
            if self.serviceDiscoveryDelayMs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(self.serviceDiscoveryDelayMs) * 1_000_000)
            }
            if self.discoverAllServices {
                if self.verbose { print("[BLE] discoverServices(nil)") }
                peripheral.discoverServices(nil)
            } else {
                // Try advertised service UUID first, then fall back to expected
                if let advSvc = self.advertisedServiceUUID {
                    if self.verbose { print("[BLE] discoverServices([advertised: \(advSvc.uuidString)])") }
                    peripheral.discoverServices([advSvc])
                } else {
                    if self.verbose { print("[BLE] discoverServices([radioServiceUUID])") }
                    peripheral.discoverServices([radioServiceUUID])
                }
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            if self.verbose {
                print("[BLE] fail to connect phase=\(self.phase.rawValue) err=\(String(describing: error))")
            }
            self.connectContinuation?.resume(throwing: error ?? CliError.connectTimeout)
            self.connectContinuation = nil
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            let msg = error.map { String(describing: $0) }
            if self.verbose {
                print("[BLE] disconnected phase=\(self.phase.rawValue) err=\(msg ?? "(nil)")")
            }
            self.phase = .idle
            for (_, cont) in self.pending {
                cont.resume(throwing: CliError.disconnected(msg))
            }
            self.pending.removeAll()
            self.connectContinuation?.resume(throwing: CliError.disconnected(msg))
            self.connectContinuation = nil
        }
    }
}

extension UVProCB: CBPeripheralDelegate {
    nonisolated func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        Task { @MainActor in
            if self.verbose {
                print("[BLE] name updated: \(peripheral.name ?? "(no name)")")
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        Task { @MainActor in
            if self.verbose {
                let ids = invalidatedServices.map { $0.uuid.uuidString }.joined(separator: ", ")
                print("[BLE] services modified: [\(ids)]")
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                self.connectContinuation?.resume(throwing: error)
                self.connectContinuation = nil
                return
            }
            guard let services = peripheral.services else { return }
            if self.verbose {
                print("[BLE] services: \(services.map { $0.uuid.uuidString }.joined(separator: ", "))")
            }
            // Look for either the expected radio service or the advertised service
            var targetUUIDs: [CBUUID] = [radioServiceUUID]
            if let advSvc = self.advertisedServiceUUID {
                targetUUIDs.append(advSvc)
            }
            for s in services where targetUUIDs.contains(s.uuid) {
                self.phase = .discoveringChars
                if self.verbose { print("[BLE] discovering chars for \(s.uuid.uuidString)") }
                peripheral.discoverCharacteristics(nil, for: s)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                self.connectContinuation?.resume(throwing: error)
                self.connectContinuation = nil
                return
            }
            guard let chars = service.characteristics else { return }
            if self.verbose {
                print("[BLE] chars for \(service.uuid.uuidString): \(chars.map { $0.uuid.uuidString }.joined(separator: ", "))")
            }
            for c in chars {
                if c.uuid == radioWriteUUID || c.uuid == radioIndicateUUID {
                    if self.verbose { print("[BLE] found expected char \(c.uuid.uuidString) props=\(c.properties.rawValue)") }
                    if c.uuid == radioWriteUUID { self.writeChar = c }
                    if c.uuid == radioIndicateUUID { self.indicateChar = c }
                }
            }
            if let ind = self.indicateChar {
                self.requestedNotify = true
                peripheral.setNotifyValue(true, for: ind)
            }
            // iOS FieldHT behavior: complete connection as soon as both chars are found.
            if self.writeChar != nil, self.indicateChar != nil {
                if self.verbose { print("[BLE] chars ready (skip notify wait - iOS style)") }
                self.phase = .ready
                self.connectContinuation?.resume()
                self.connectContinuation = nil
            } else if self.verbose {
                print("[BLE] chars discovered; write=\(self.writeChar != nil ? 1 : 0) ind=\(self.indicateChar != nil ? 1 : 0)")
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            if characteristic.uuid != radioIndicateUUID { return }
            if let error {
                if self.verbose { print("[BLE] notify state error: \(error)") }
                return
            }
            self.notifyReady = characteristic.isNotifying
            if self.verbose { print("[BLE] notify state updated: isNotifying=\(characteristic.isNotifying ? 1 : 0)") }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error {
                if self.verbose { print("[BLE-RX] error: \(error)") }
                return
            }
            guard characteristic.uuid == radioIndicateUUID, let value = characteristic.value else { return }
            if self.verbose {
                print("[BLE-RX] raw (\(value.count)): \(hex(value))")
            }
            let msg: ProtoMsg
            do {
                msg = try decodeMessage(value)
            } catch {
                if self.verbose { print("[BLE-RX] decode failed: \(error)") }
                return
            }
            if self.verbose {
                print("[BLE-RX] decoded reply=\(msg.isReply) grp=\(msg.group) cmd=\(msg.command) body=\(hex(msg.body))")
            }
            guard msg.isReply else { return }
            let key: UInt32 = (UInt32(msg.group) << 16) | UInt32(msg.command)
            if let cont = self.pending.removeValue(forKey: key) {
                cont.resume(returning: msg)
            }
        }
    }
}

private func withTimeout<T>(seconds: Double, label: String, _ op: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await op() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw CliError.timeout(label)
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

private func decodeReplyStatus(_ body: Data) throws -> UInt8 {
    guard let b = body.first else { throw CliError.badReply("empty body") }
    return b
}

private func decodeRegionNameReply(_ body: Data) throws -> (status: UInt8, regionEcho: UInt8, name: String) {
    guard body.count >= 2 else { throw CliError.badReply("readRegionName body too short") }
    let status = body[0]
    let regionEcho = body[1]
    let nameRaw = body.subdata(in: 2..<body.count)
    let cut = nameRaw.split(separator: 0, maxSplits: 1, omittingEmptySubsequences: false).first ?? Data()
    let name = String(decoding: cut, as: UTF8.self)
    return (status, regionEcho, name)
}

private func getRegionNames(uv: UVProCB, maxRegions: Int) async throws -> [String] {
    var out: [String] = []
    for i in 0..<maxRegions {
        let msg = try await uv.sendAndWait(group: 2, command: 73, body: Data([UInt8(i & 0xFF)]), timeoutS: 3.0)
        let (st, echo, name) = try decodeRegionNameReply(msg.body)
        if st != 0 { break }
        if echo != UInt8(i & 0xFF) {
            print("[WARN] echo mismatch requested=\(i) reply=\(echo)")
        }
        out.append(name)
    }
    return out
}

private func tryRenameID(uv: UVProCB, idx: Int, name: String) async throws {
    let body = Data([UInt8(idx & 0xFF)]) + encodeName10(name)
    let msg = try await uv.sendAndWait(group: 2, command: 59, body: body, timeoutS: 3.0)
    let st = try decodeReplyStatus(msg.body)
    if st != 0 { throw CliError.badReply("writeRegionName(id+name) status=\(st)") }
}

private func tryRenameCurrent(uv: UVProCB, idx: Int, name: String, settleMs: Int = 250) async throws {
    var msg = try await uv.sendAndWait(group: 2, command: 60, body: Data([UInt8(idx & 0xFF)]), timeoutS: 3.0)
    var st = try decodeReplyStatus(msg.body)
    if st != 0 { throw CliError.badReply("setRegion status=\(st)") }
    try await Task.sleep(nanoseconds: UInt64(settleMs) * 1_000_000)
    msg = try await uv.sendAndWait(group: 2, command: 59, body: encodeName10(name), timeoutS: 3.0)
    st = try decodeReplyStatus(msg.body)
    if st != 0 { throw CliError.badReply("writeRegionName(name-only) status=\(st)") }
}

private func diffIndices(_ a: [String], _ b: [String]) -> [Int] {
    let n = min(a.count, b.count)
    var out: [Int] = []
    for i in 0..<n where a[i] != b[i] { out.append(i) }
    return out
}

@MainActor
private func runMain() async throws {
    print("[UVPRO-CB] starting")
    var args = CommandLine.arguments.dropFirst()

    func pop(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag) else { return nil }
        let j = args.index(after: i)
        guard j < args.endIndex else { return nil }
        let v = args[j]
        args.remove(at: j)
        args.remove(at: i)
        return v
    }

    func has(_ flag: String) -> Bool {
        if let i = args.firstIndex(of: flag) {
            args.remove(at: i)
            return true
        }
        return false
    }

    if has("--help") || has("-h") {
        print(
            """
Usage:
  uvpro_cb_test --list [--scan-timeout S] [--verbose]
  uvpro_cb_test --read --uuid UUID [--no-pairing-filter] [--discover-all-services] [--service-discovery-delay-ms MS] [--verbose]
  uvpro_cb_test --rename INDEX NAME --uuid UUID [--no-restore] [--no-pairing-filter] [--discover-all-services] [--verbose]
  uvpro_cb_test --matrix INDEX --uuid UUID [--no-restore] [--no-pairing-filter] [--discover-all-services] [--verbose]

Notes:
  - If UV-PRO doesn't advertise a name on macOS, use --uuid.
  - Default connect filter expects pairing service 88A1; disable with --no-pairing-filter.
"""
        )
        return
    }

    let verbose = has("--verbose")
    let list = has("--list")
    let noRestore = has("--no-restore")
    let nameContains = pop("--name-contains") ?? "UV-PRO"
    let scanTimeoutS = Double(pop("--scan-timeout") ?? "8") ?? 8
    let connectTimeoutS = Double(pop("--connect-timeout") ?? "12") ?? 12
    let svcDelayMs = Int(pop("--service-discovery-delay-ms") ?? "0") ?? 0
    let requirePairingService = !has("--no-pairing-filter")
    let discoverAllServices = has("--discover-all-services")
    let maxRegions = Int(pop("--max-regions") ?? "16") ?? 16

    let uuidStr = pop("--uuid")
    let targetUUID = uuidStr.flatMap(UUID.init(uuidString:))

    let cmdRead = has("--read")
    var cmdRename: (Int, String)? = nil
    if let i = args.firstIndex(of: "--rename") {
        guard i + 2 < args.endIndex else { throw CliError.badArgs("--rename INDEX NAME") }
        let idx = Int(args[args.index(after: i)])
        let name = args[args.index(i, offsetBy: 2)]
        guard let idx else { throw CliError.badArgs("--rename INDEX NAME") }
        cmdRename = (idx, name)
        args.removeSubrange(i...args.index(i, offsetBy: 2))
    }
    var cmdMatrix: Int? = nil
    if let i = args.firstIndex(of: "--matrix") {
        guard i + 1 < args.endIndex else { throw CliError.badArgs("--matrix INDEX") }
        let idx = Int(args[args.index(after: i)])
        guard let idx else { throw CliError.badArgs("--matrix INDEX") }
        cmdMatrix = idx
        args.removeSubrange(i...args.index(after: i))
    }

    let uv = UVProCB()
    uv.setServiceDiscoveryDelayMs(svcDelayMs)
    uv.setDiscoverAllServices(discoverAllServices)
    try await uv.connect(
        nameContains: nameContains.isEmpty ? nil : nameContains,
        targetUUID: targetUUID,
        scanTimeoutS: scanTimeoutS,
        connectTimeoutS: connectTimeoutS,
        listOnly: list,
        requirePairingService: requirePairingService,
        discoverAllServices: discoverAllServices,
        verbose: verbose
    )

    if list {
        uv.listDiscovered()
        uv.disconnect()
        return
    }

    let before = try await getRegionNames(uv: uv, maxRegions: maxRegions)
    print("[REGIONS] Before:")
    for (i, n) in before.enumerated() {
        print("  \(i): \(n.isEmpty ? "(empty)" : n)")
    }

    if cmdRead || (cmdRename == nil && cmdMatrix == nil) {
        uv.disconnect()
        return
    }

    let original = before

    if let (idx, newName) = cmdRename {
        print("[RENAME] target=\(idx) name='\(newName)'")
        do {
            print("[RENAME] current-region path: setRegion(\(idx)) + write(name-only)")
            try await tryRenameCurrent(uv: uv, idx: idx, name: newName)
        } catch {
            print("[RENAME] current-region path failed: \(error)")
            print("[RENAME] fallback path: write(id+name)")
            try await tryRenameID(uv: uv, idx: idx, name: newName)
        }
        let after = try await getRegionNames(uv: uv, maxRegions: maxRegions)
        print("[REGIONS] Changed indices: \(diffIndices(before, after))")
        print("[REGIONS] After:")
        for (i, n) in after.enumerated() {
            print("  \(i): \(n.isEmpty ? "(empty)" : n)")
        }

        if !noRestore {
            print("[RESTORE] restoring original names")
            for (i, old) in original.enumerated() {
                do { try await tryRenameCurrent(uv: uv, idx: i, name: old) }
                catch { try await tryRenameID(uv: uv, idx: i, name: old) }
            }
            print("[RESTORE] done")
        }
        uv.disconnect()
        return
    }

    if let idx = cmdMatrix {
        let a = "T\(idx)A"
        let b = "T\(idx)B"
        let c = "T\(idx)C"
        print("[MATRIX] target=\(idx)")
        print("[MATRIX] A: write(id+name) -> '\(a)'")
        try await tryRenameID(uv: uv, idx: idx, name: a)
        let afterA = try await getRegionNames(uv: uv, maxRegions: maxRegions)
        print("[MATRIX] A changed: \(diffIndices(before, afterA))")

        print("[MATRIX] B: setRegion + write(name-only) -> '\(b)'")
        try await tryRenameCurrent(uv: uv, idx: idx, name: b)
        let afterB = try await getRegionNames(uv: uv, maxRegions: maxRegions)
        print("[MATRIX] B changed: \(diffIndices(afterA, afterB))")

        print("[MATRIX] C: setRegion + write(id+name) -> '\(c)'")
        _ = try await uv.sendAndWait(group: 2, command: 60, body: Data([UInt8(idx & 0xFF)]), timeoutS: 3.0)
        try await Task.sleep(nanoseconds: 250_000_000)
        try await tryRenameID(uv: uv, idx: idx, name: c)
        let afterC = try await getRegionNames(uv: uv, maxRegions: maxRegions)
        print("[MATRIX] C changed: \(diffIndices(afterB, afterC))")

        if !noRestore {
            print("[RESTORE] restoring original names")
            for (i, old) in original.enumerated() {
                do { try await tryRenameCurrent(uv: uv, idx: i, name: old) }
                catch { try await tryRenameID(uv: uv, idx: i, name: old) }
            }
            print("[RESTORE] done")
        }
        uv.disconnect()
        return
    }

    uv.disconnect()
}

Task { @MainActor in
    do {
        try await runMain()
        exit(0)
    } catch {
        print("ERROR: \(error)")
        exit(1)
    }
}
dispatchMain()
