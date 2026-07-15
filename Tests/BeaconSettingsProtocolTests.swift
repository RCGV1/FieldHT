import Foundation

enum ProtocolError: Error {
    case invalidCommandGroup
    case invalidPowerStatusType
    case decodeError(String)
}

@main
enum BeaconSettingsProtocolTests {
    static func main() {
        var failures = 0

        func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
            if actual != expected {
                failures += 1
                fputs("FAIL: \(message). Expected \(expected), got \(actual)\n", stderr)
            }
        }

        let extended = BeaconSettings(
            maxFwdTimes: 2,
            timeToLive: 3,
            pttReleaseSendLocation: true,
            pttReleaseSendIDInfo: false,
            pttReleaseSendBSSUserID: false,
            shouldShareLocation: true,
            sendPwrVoltage: true,
            packetFormat: .aprs,
            allowPositionCheck: true,
            aprsSSID: 7,
            locationShareInterval: 300,
            bssUserID: 0,
            pttReleaseIDInfo: "N6CH",
            beaconMessage: "FieldHT",
            aprsSymbol: "/>",
            aprsCallsign: "N6CH",
            smartBeaconEnabled: true,
            micEEnabled: true,
            sendIDByAPRS: true,
            smartBeaconMinimumInterval: 5,
            smartBeaconMaximumInterval: 30
        )

        let extendedData = ProtocolEncoder.encodeBeaconSettings(extended)
        expectEqual(extendedData.count, 52, "extended beacon settings use the UV-PRO V2 payload size")

        do {
            let decoded = try ProtocolDecoder.decodeBeaconSettings(extendedData)
            expectEqual(decoded.smartBeaconEnabled, true, "smart beacon enable round trips")
            expectEqual(decoded.micEEnabled, true, "Mic-E enable round trips")
            expectEqual(decoded.sendIDByAPRS, true, "send ID by APRS round trips")
            expectEqual(decoded.smartBeaconMinimumInterval, 5, "smart beacon minimum interval round trips")
            expectEqual(decoded.smartBeaconMaximumInterval, 30, "smart beacon maximum interval round trips")
        } catch {
            failures += 1
            fputs("FAIL: extended beacon settings should decode: \(error)\n", stderr)
        }

        let legacy = BeaconSettings(
            maxFwdTimes: 0,
            timeToLive: 0,
            pttReleaseSendLocation: false,
            pttReleaseSendIDInfo: false,
            pttReleaseSendBSSUserID: false,
            shouldShareLocation: false,
            sendPwrVoltage: false,
            packetFormat: .bss,
            allowPositionCheck: false,
            aprsSSID: 0,
            locationShareInterval: 0,
            bssUserID: 0,
            pttReleaseIDInfo: "",
            beaconMessage: "",
            aprsSymbol: "",
            aprsCallsign: "",
            smartBeaconEnabled: false,
            smartBeaconMinimumInterval: nil,
            smartBeaconMaximumInterval: nil
        )
        expectEqual(ProtocolEncoder.encodeBeaconSettings(legacy).count, 50, "legacy beacon settings retain their existing payload size")

        let aprsPath = "WIDE1-1,WIDE2-99,custom!"
        expectEqual(
            String(data: ProtocolEncoder.encodeAPRSPath(aprsPath), encoding: .utf8),
            "WIDE1-1,WIDE2-8,custom",
            "APRS path matches the vendor app's repeater sanitization"
        )
        expectEqual(
            ProtocolDecoder.decodeAPRSPath(Data("WIDE1-1,WIDE2-2\0".utf8)),
            "WIDE1-1,WIDE2-2",
            "APRS path replies trim radio null padding"
        )

        if failures > 0 {
            exit(1)
        }

        print("BeaconSettingsProtocolTests passed")
    }
}
