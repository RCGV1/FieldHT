import XCTest
@testable import FieldHT

final class SettingsProtocolTests: XCTestCase {
    func testScreenTimeoutEncodingClampsToFiveBitProtocolRange() throws {
        var settings = Settings.empty()
        settings.screenTimeout = 300

        let encoded = ProtocolEncoder.encodeSettings(settings)
        let decoded = try ProtocolDecoder.decodeSettings(encoded)

        XCTAssertEqual(decoded.screenTimeout, Settings.maxScreenTimeout)
    }

    func testScreenTimeoutUpdateValuesStayWithinVerifiedRange() {
        XCTAssertEqual(Settings.selectableScreenTimeouts.max(), Settings.maxScreenTimeout)
        XCTAssertFalse(Settings.selectableScreenTimeouts.contains { $0 > Settings.maxScreenTimeout })
    }
}
