import XCTest
@testable import FieldHT

@MainActor
final class ConnectionUXTests: XCTestCase {
    private func makeManager() -> RadioManager {
        let suite = "FieldHT.ConnectionUXTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return RadioManager(restoreSavedRadio: false, defaults: defaults)
    }

    func testCancelPausesRadioWithoutForgettingOrChangingPreference() async {
        let manager = makeManager()
        let saved = UUID()
        manager.lastPairedDeviceUUID = saved
        manager.isConnecting = true
        manager.isAutoReconnecting = true
        manager.connectionError = "Connecting"

        manager.cancelRadioConnection()
        XCTAssertTrue(manager.isRadioReconnectPaused)
        XCTAssertFalse(manager.isConnecting)
        XCTAssertFalse(manager.isAutoReconnecting)
        XCTAssertNil(manager.connectionError)
        XCTAssertEqual(manager.lastPairedDeviceUUID, saved)
        XCTAssertTrue(manager.autoReconnectEnabled)

        manager.handleTransportBluetoothAvailable()
        await Task.yield()
        XCTAssertFalse(manager.isConnecting)
        XCTAssertFalse(manager.isAutoReconnecting)
    }

    func testImmediateCancelOfNewSelectionKeepsLastSuccessfulRadio() async {
        let manager = makeManager()
        let saved = UUID()
        manager.lastPairedDeviceUUID = saved
        manager.connect(to: UUID())
        manager.cancelRadioConnection()
        await Task.yield()
        XCTAssertEqual(manager.lastPairedDeviceUUID, saved)
        XCTAssertFalse(manager.isConnecting)
        XCTAssertTrue(manager.isRadioReconnectPaused)
    }

    func testAutomaticReconnectCanBeDisabledDuringAnAttempt() async {
        let manager = makeManager()
        manager.lastPairedDeviceUUID = UUID()
        manager.isConnecting = true
        manager.isAutoReconnecting = true
        manager.autoReconnectEnabled = false
        manager.handleTransportBluetoothAvailable()
        await Task.yield()
        XCTAssertFalse(manager.isConnecting)
        XCTAssertFalse(manager.isAutoReconnecting)
        XCTAssertFalse(manager.autoReconnectEnabled)
        XCTAssertNotNil(manager.lastPairedDeviceUUID)
    }

    func testSpeakerMicCancelDoesNotDisconnectRadioOrForgetMic() async {
        let manager = makeManager()
        let mic = UUID()
        manager.isConnected = true
        manager.lastSpeakerMicDeviceUUID = mic
        manager.isSpeakerMicConnecting = true
        manager.cancelSpeakerMicConnection()
        await Task.yield()
        XCTAssertFalse(manager.isSpeakerMicConnecting)
        XCTAssertTrue(manager.isConnected)
        XCTAssertEqual(manager.lastSpeakerMicDeviceUUID, mic)
        XCTAssertNil(manager.speakerMicConnectionError)
    }

    func testForgettingSpeakerMicOnlyClearsAccessorySelection() async {
        let manager = makeManager()
        let radio = UUID()
        manager.isConnected = true
        manager.lastPairedDeviceUUID = radio
        manager.lastSpeakerMicDeviceUUID = UUID()
        manager.forgetLastSpeakerMic()
        await Task.yield()
        XCTAssertNil(manager.lastSpeakerMicDeviceUUID)
        XCTAssertEqual(manager.lastPairedDeviceUUID, radio)
        XCTAssertTrue(manager.isConnected)
    }

    func testAutomaticRetriesAreBounded() {
        XCTAssertTrue(ConnectionUXPolicy.shouldRetryRadio(afterFailedAttempts: 1))
        XCTAssertTrue(ConnectionUXPolicy.shouldRetryRadio(afterFailedAttempts: 2))
        XCTAssertFalse(ConnectionUXPolicy.shouldRetryRadio(afterFailedAttempts: 3))
        XCTAssertFalse(ConnectionUXPolicy.shouldRetryRadio(afterFailedAttempts: 100))
        XCTAssertEqual(ConnectionUXPolicy.scanDuration, 15)
    }
}
