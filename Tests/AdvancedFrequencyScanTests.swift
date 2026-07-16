import Foundation

@main
enum AdvancedFrequencyScanTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let scanURL = root.appending(path: "FieldHT/Views/AdvancedFrequencyScanView.swift")
        let settingsURL = root.appending(path: "FieldHT/Views/ScanSettingsView.swift")
        let radioManagerURL = root.appending(path: "FieldHT/ViewModels/RadioManager.swift")
        let encoderURL = root.appending(path: "FieldHT/Protocol/ProtocolEncoder.swift")
        let decoderURL = root.appending(path: "FieldHT/Protocol/ProtocolDecoder.swift")
        let messageURL = root.appending(path: "FieldHT/Command/RadioMessage.swift")
        let controllerURL = root.appending(path: "FieldHT/RadioController.swift")
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
            expect(scan.contains("enum ScanOperationState"), "advanced frequency scan must model idle, scanning, and held states")
            expect(scan.contains("holdScan"), "advanced frequency scan must provide a hold action")
            expect(scan.contains("resumeScan"), "advanced frequency scan must provide a resume action")
            expect(scan.contains("struct ScanHit"), "advanced frequency scan must retain detected frequencies")
            expect(scan.contains("func recordHit"), "advanced frequency scan must record radio-reported tuned frequencies")
            expect(scan.contains("maxRecentHits"), "advanced frequency scan history must remain bounded")
            expect(scan.contains("AdvancedScanSetupView"), "advanced frequency scan configuration must move out of the operating surface")
            expect(scan.contains("Recent Hits"), "advanced frequency scan must expose detected frequencies")
            expect(scan.contains("Band Presets"), "advanced frequency scan setup must offer common operator band presets")
            expect(scan.contains("applyPreset"), "advanced frequency scan must apply band presets consistently")
            expect(scan.contains("GlassEffectContainer"), "native scan controls must use the iOS liquid glass container when available")
            expect(scan.contains("buttonStyle(.glass)"), "native scan controls must use the iOS glass button style when available")
            expect(scan.contains("rxSubAudio"), "scan hits must retain the radio-reported receive tone")
            expect(scan.contains("onDelete"), "recent scan hits must support swipe deletion")
            expect(scan.contains("ScanHitSaveSheet"), "scan hits must open a memory-slot save sheet")
            expect(scan.contains("if case .held = operation"), "fine tuning must only appear while the scan is held")
        }

        let settings = try String(contentsOf: settingsURL, encoding: .utf8)
        expect(settings.contains("Advanced Frequency Scan"), "scan settings must link to advanced frequency scan")

        let radioManager = try String(contentsOf: radioManagerURL, encoding: .utf8)
        expect(radioManager.contains("func setFrequencyScan"), "radio manager must expose native frequency scanning")

        let encoder = try String(contentsOf: encoderURL, encoding: .utf8)
        expect(encoder.contains("stream.writeInt(mode.rawValue, bitCount: 4)"), "frequency mode payload must encode the requested mode")
        expect(!encoder.contains("reserved1: UInt16 = 0x0A00"), "frequency mode payload must not hard-code satellite mode")
        expect(encoder.contains("encodeWriteRegionChannel"), "protocol encoder must write a full memory group channel")

        let decoder = try String(contentsOf: decoderURL, encoding: .utf8)
        expect(decoder.contains("let rxSubAudio = decodeSubAudio"), "frequency status must decode the detected receive tone")

        let message = try String(contentsOf: messageURL, encoding: .utf8)
        expect(message.contains("public let rxSubAudio: SubAudio?"), "frequency status must expose the detected receive tone")

        let controller = try String(contentsOf: controllerURL, encoding: .utf8)
        expect(controller.contains("saveScanHit"), "radio controller must save scan results to the selected memory group slot")

        if failures > 0 {
            exit(1)
        }

        print("AdvancedFrequencyScanTests passed")
    }
}
