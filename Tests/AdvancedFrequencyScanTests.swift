import Foundation

@main
enum AdvancedFrequencyScanTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let scanURL = root.appending(path: "FieldHT/Views/AdvancedFrequencyScanView.swift")
        let settingsURL = root.appending(path: "FieldHT/Views/ScanSettingsView.swift")
        let radioManagerURL = root.appending(path: "FieldHT/ViewModels/RadioManager.swift")
        let encoderURL = root.appending(path: "FieldHT/Protocol/ProtocolEncoder.swift")
        var failures = 0

        func expect(_ condition: Bool, _ message: String) {
            if !condition {
                failures += 1
                fputs("FAIL: \(message)\n", stderr)
            }
        }

        expect(FileManager.default.fileExists(atPath: scanURL.path), "advanced frequency scan view must exist")

        if let scan = try? String(contentsOf: scanURL, encoding: .utf8) {
            expect(scan.contains("scanStepKHz"), "advanced frequency scan must offer a scan step")
            expect(scan.contains("fineTuningStepKHz"), "advanced frequency scan must offer a fine-tuning step")
            expect(scan.contains("startMHz"), "advanced frequency scan must support a start frequency")
            expect(scan.contains("endMHz"), "advanced frequency scan must support an end frequency")
            expect(scan.contains("setFrequencyScan"), "advanced frequency scan must use the radio's native scan command")
            expect(scan.contains(".scanUp"), "advanced frequency scan must start native upward scans")
            expect(scan.contains(".scanDown"), "advanced frequency scan must start native downward scans")
            expect(scan.contains(".off"), "advanced frequency scan must stop the native scan mode")
            expect(scan.contains("startRapidScan"), "advanced frequency scan must start an automatic range scan")
            expect(scan.contains("stopRapidScan"), "advanced frequency scan must stop an automatic range scan")
            expect(scan.contains("pauseOnSignal"), "advanced frequency scan must be able to pause on an active signal")
        }

        let settings = try String(contentsOf: settingsURL, encoding: .utf8)
        expect(settings.contains("Advanced Frequency Scan"), "scan settings must link to advanced frequency scan")

        let radioManager = try String(contentsOf: radioManagerURL, encoding: .utf8)
        expect(radioManager.contains("func setFrequencyScan"), "radio manager must expose native frequency scanning")

        let encoder = try String(contentsOf: encoderURL, encoding: .utf8)
        expect(encoder.contains("stream.writeInt(mode.rawValue, bitCount: 4)"), "frequency mode payload must encode the requested mode")
        expect(!encoder.contains("reserved1: UInt16 = 0x0A00"), "frequency mode payload must not hard-code satellite mode")

        if failures > 0 {
            exit(1)
        }

        print("AdvancedFrequencyScanTests passed")
    }
}
