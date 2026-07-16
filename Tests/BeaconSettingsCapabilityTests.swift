import Foundation

@main
enum BeaconSettingsCapabilityTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = try String(
            contentsOf: root.appending(path: "FieldHT/Views/BeaconSettingsView.swift"),
            encoding: .utf8
        )
        var failures = 0

        func expect(_ condition: Bool, _ message: String) {
            if !condition {
                failures += 1
                fputs("FAIL: \(message)\n", stderr)
            }
        }

        expect(source.contains("firmwareVersion >= 86"), "APRS paths must be gated to stock-supported firmware")
        expect(source.contains("firmwareVersion >= 135"), "Mic-E must be gated to stock-supported firmware")
        expect(source.contains("firmwareVersion >= 138"), "APRS ID sending must be gated to stock-supported firmware")
        expect(source.contains("firmwareVersion >= 146"), "extended smart beacon intervals must be gated to stock-supported firmware")
        expect(source.contains("supportsMicE"), "the Beacon UI must not expose Mic-E on unsupported firmware")
        expect(source.contains("supportsSendIDByAPRS"), "the Beacon UI must not expose APRS ID sending on unsupported firmware")
        expect(source.contains("supportsExtendedSmartBeaconing"), "the Beacon UI must gate extended smart beacon controls")

        if failures > 0 {
            exit(1)
        }

        print("BeaconSettingsCapabilityTests passed")
    }
}
