import Foundation

struct BLECaptureFileInfo: Identifiable {
    let id: String
    let title: String
    let url: URL
    let sizeBytes: Int

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }
}

actor BLECaptureStore {
    static let shared = BLECaptureStore()
    static let defaultsKey = "com.fieldHT.debug.bleCapture"
    static let defaultEnabled = true

    private let maxBytes: Int = 5 * 1024 * 1024
    private let fileName = "fieldht_ble_capture.jsonl"
    private let rotatedFileName = "fieldht_ble_capture.jsonl.1"

    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: defaultsKey) == nil {
            return defaultEnabled
        }
        return defaults.bool(forKey: defaultsKey)
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.defaultsKey)
    }

    func currentLogURL() -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return caches.appendingPathComponent(fileName, isDirectory: false)
    }

    func rotatedLogURL() -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return caches.appendingPathComponent(rotatedFileName, isDirectory: false)
    }

    func availableFiles() -> [BLECaptureFileInfo] {
        let fm = FileManager.default
        let candidates: [(String, URL?)] = [
            ("Current Capture", currentLogURL()),
            ("Previous Capture", rotatedLogURL())
        ]

        return candidates.compactMap { title, url in
            guard let url,
                  fm.fileExists(atPath: url.path),
                  let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? NSNumber
            else {
                return nil
            }

            return BLECaptureFileInfo(
                id: title,
                title: title,
                url: url,
                sizeBytes: size.intValue
            )
        }
    }

    func clear() {
        let fm = FileManager.default
        if let url = currentLogURL() {
            try? fm.removeItem(at: url)
        }
        if let url = rotatedLogURL() {
            try? fm.removeItem(at: url)
        }
    }

    func recordPacket(direction: String, characteristicUUID: String, data: Data) {
        let hex = data.map { String(format: "%02hhx", $0) }.joined()
        append(entry: [
            "entry": "packet",
            "dir": direction,
            "uuid": characteristicUUID.lowercased(),
            "len": data.count,
            "hex": hex
        ])
    }

    func recordNote(category: String, message: String, fields: [String: String] = [:]) {
        append(entry: [
            "entry": "note",
            "category": category,
            "message": message,
            "fields": fields
        ])
    }

    private func rotateIfNeeded(at url: URL) {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber
        else { return }

        if size.intValue < maxBytes { return }

        guard let rotated = rotatedLogURL() else { return }
        _ = try? fm.removeItem(at: rotated)
        _ = try? fm.moveItem(at: url, to: rotated)
    }

    private func append(entry: [String: Any]) {
        guard let url = currentLogURL() else { return }
        let fm = FileManager.default

        if !fm.fileExists(atPath: url.path) {
            _ = fm.createFile(atPath: url.path, contents: nil)
        } else {
            rotateIfNeeded(at: url)
        }

        var payload = entry
        payload["unix_ms"] = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())

        guard JSONSerialization.isValidJSONObject(payload),
              let lineData = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let newline = "\n".data(using: .utf8)
        else {
            return
        }

        do {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: lineData)
            try handle.write(contentsOf: newline)
            try handle.close()
        } catch {
            // Best-effort only.
        }
    }
}
