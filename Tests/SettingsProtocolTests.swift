import Foundation

enum ProtocolError: Error {
    case invalidCommandGroup
    case invalidPowerStatusType
    case decodeError(String)
}

@main
enum SettingsProtocolTests {
    static func main() {
        var failures = 0

        func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
            if actual != expected {
                failures += 1
                fputs("FAIL: \(message). Expected \(expected), got \(actual)\n", stderr)
            }
        }

        var settings = Settings.empty()
        settings.autoShareLocCh = 200
        settings.kissEnabled = true
        settings.kissUploadTxMessage = true
        settings.kissTxDelay = 42
        settings.kissTxTail = 17
        settings.voxEnabled = true
        settings.voxLevel = 5
        settings.disableBluetoothMic = true
        settings.voxDelay = 4
        settings.noiseSuppressionEnabled = true
        settings.alarmVolume = 6
        settings.useCustomLocation = true
        settings.gpwplUploadEnabled = true
        settings.vfo1ModFreqX = 1
        settings.rawExtensionData = Data([0xAA, 0x55])

        do {
            let decoded = try ProtocolDecoder.decodeSettings(ProtocolEncoder.encodeSettings(settings))
            expectEqual(decoded.autoShareLocCh, 200, "beacon transmit channel preserves all eight bits")
            expectEqual(decoded.kissEnabled, true, "KISS enabled survives a settings round trip")
            expectEqual(decoded.kissUploadTxMessage, true, "KISS upload survives a settings round trip")
            expectEqual(decoded.kissTxDelay, 42, "KISS TX delay survives a settings round trip")
            expectEqual(decoded.kissTxTail, 17, "KISS TX tail survives a settings round trip")
            expectEqual(decoded.voxEnabled, true, "VOX enabled survives a settings round trip")
            expectEqual(decoded.voxLevel, 5, "VOX level survives a settings round trip")
            expectEqual(decoded.disableBluetoothMic, true, "Bluetooth mic disable survives a settings round trip")
            expectEqual(decoded.voxDelay, 4, "VOX delay survives a settings round trip")
            expectEqual(decoded.noiseSuppressionEnabled, true, "Noise suppression survives a settings round trip")
            expectEqual(decoded.alarmVolume, 6, "Prompt and tone volume survives a settings round trip")
            expectEqual(decoded.useCustomLocation, true, "Custom location setting survives a settings round trip")
            expectEqual(decoded.gpwplUploadEnabled, true, "GPWPL upload setting survives a settings round trip")
            expectEqual(decoded.vfo1ModFreqX, 1, "VFO extension bit survives a settings round trip")
            expectEqual(decoded.rawExtensionData, Data([0xAA, 0x55]), "Extension data is preserved")
        } catch {
            failures += 1
            fputs("FAIL: settings payload should round trip: \(error)\n", stderr)
        }

        if failures > 0 {
            exit(1)
        }

        print("SettingsProtocolTests passed")
    }
}
