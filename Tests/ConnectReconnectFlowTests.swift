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
        expect(connect.contains("if hasSavedRadio {\n                    Toggle(\"Reconnect Automatically\""), "automatic reconnect must remain configurable while disconnected or retrying")
        expect(connect.contains("radio.cancelConnection"), "an in-flight radio connection must expose a Cancel action")
        expect(connect.contains("Choose Another Radio"), "a saved-radio attempt must not block choosing another radio")
        let disconnected = try String(contentsOf: root.appending(path: "FieldHT/Views/NotConnectedView.swift"), encoding: .utf8)
        expect(disconnected.contains("radioManager.cancelRadioConnection()"), "reconnecting must also be cancellable from the disconnected Radio and Settings screens")
        expect(!connect.contains("validateRadioService"), "selecting a radio must not start a competing scanner-owned BLE connection")
        expect(!connect.contains("DispatchQueue.main.asyncAfter"), "a cancelled selection must not leave a delayed connect callback")
        expect(!transport.contains("case .poweredOff, .unauthorized, .unsupported, .resetting, .unknown:"), "transient CoreBluetooth states must not fail a reconnect")
        expect(transport.contains("failConnect(BLEError.bluetoothPoweredOff)"), "powered-off Bluetooth must be identified separately")
        expect(transport.contains("failConnect(BLEError.bluetoothUnauthorized)"), "denied Bluetooth access must have a permission-specific failure")
        expect(!transport.contains("case .poweredOff, .unauthorized, .unsupported:"), "a transient unsupported startup report must not end a reconnect")
        expect(connect.contains("UIApplication.openSettingsURLString"), "denied access must offer an Open Settings action")
        let manager = try String(contentsOf: root.appending(path: "FieldHT/ViewModels/RadioManager.swift"), encoding: .utf8)
        let reconnectStart = manager.range(of: "    private func startAutoReconnect")!.lowerBound
        let reconnectEnd = manager.range(of: "    private func nextReconnectDelaySeconds")!.lowerBound
        let loop = manager[reconnectStart..<reconnectEnd]
        expect(!loop.contains("autoReconnectEnabled = false"), "Bluetooth failures must preserve the user's automatic reconnect preference")
        expect(loop.contains("await cleanup.value"), "new reconnects must wait for old transport cleanup")
        expect(loop.contains("self.connectionGeneration == generation"), "stale reconnect completions must not overwrite a newer session")
        expect(manager.contains("handleTransportBluetoothAvailable"), "Bluetooth returning must wake saved-radio reconnects")
        expect(loop.contains("ConnectionUXPolicy.shouldRetryRadio"), "automatic attempts must have a finite retry limit")
        expect(loop.contains("self.isRadioReconnectPaused = true"), "exhausted reconnects must pause until the user chooses to resume")
        let speaker = try String(contentsOf: root.appending(path: "FieldHT/Views/SpeakerMicView.swift"), encoding: .utf8)
        expect(!speaker.contains("autoReconnectSavedSpeakerMic"), "opening Speaker Mic must not automatically reconnect an absent accessory")
        expect(speaker.contains("speakerMic.cancelConnection"), "speaker-mic attempts must have an explicit Cancel action")
        expect(speaker.contains("if let savedUUID = radioManager.lastSpeakerMicDeviceUUID"), "a saved mic must remain retryable when it is absent from discovery")
        expect(speaker.contains("scanner.stopScanning()\n            radioManager.cancelSpeakerMicConnection()"), "leaving speaker-mic setup must stop discovery and pending setup attempts")
        let scanner = try String(contentsOf: root.appending(path: "FieldHT/BLE/BLEScanner.swift"), encoding: .utf8)
        expect(scanner.contains("Task.sleep(for: .seconds(ConnectionUXPolicy.scanDuration))"), "device discovery must stop after a bounded interval")
        expect(!scanner.contains("        checkForPreviouslyPairedDevice()"), "cached devices must not be injected as nearby scan results")

        if failures > 0 {
            exit(1)
        }

        print("ConnectReconnectFlowTests passed")
    }
}
