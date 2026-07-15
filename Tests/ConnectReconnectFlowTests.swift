import Foundation

@main
enum ConnectReconnectFlowTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let connect = try String(contentsOf: root.appending(path: "FieldHT/Views/ConnectView.swift"), encoding: .utf8)
        let transport = try String(contentsOf: root.appending(path: "FieldHT/BLE/BLEConnection.swift"), encoding: .utf8)
        var failures = 0

        func expect(_ condition: Bool, _ message: String) {
            if !condition {
                failures += 1
                fputs("FAIL: \(message)\n", stderr)
            }
        }

        expect(connect.contains("reconnectSavedRadio"), "a saved radio must have a reconnect action without a scanner result")
        expect(connect.contains("shouldShowPairingInstructions"), "pairing instructions must be conditional")
        expect(connect.contains("if !radioManager.isConnected"), "connected state must not render the nearby-radio setup flow")
        expect(connect.contains("if radioManager.isConnected, hasSavedRadio"), "automatic reconnect must only be configurable while the saved radio is connected")
        expect(!transport.contains("case .poweredOff, .unauthorized, .unsupported, .resetting, .unknown:"), "transient CoreBluetooth states must not fail a reconnect")
        expect(transport.contains("case .poweredOff, .unauthorized:"), "only definitive Bluetooth failures should end a reconnect")
        expect(!transport.contains("case .poweredOff, .unauthorized, .unsupported:"), "a transient unsupported startup report must not end a reconnect")

        if failures > 0 {
            exit(1)
        }

        print("ConnectReconnectFlowTests passed")
    }
}
