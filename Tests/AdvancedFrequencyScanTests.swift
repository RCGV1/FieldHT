import Foundation

@main
enum AdvancedFrequencyScanTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let scanURL = root.appending(path: "FieldHT/Views/AdvancedFrequencyScanView.swift")
        let settingsURL = root.appending(path: "FieldHT/Views/ScanSettingsView.swift")
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
            expect(scan.contains("setFreqModeParameters"), "advanced frequency scan must tune through the existing radio command")
        }

        let settings = try String(contentsOf: settingsURL, encoding: .utf8)
        expect(settings.contains("Advanced Frequency Scan"), "scan settings must link to advanced frequency scan")

        if failures > 0 {
            exit(1)
        }

        print("AdvancedFrequencyScanTests passed")
    }
}
