import Foundation

enum ToneParser {
    enum Kind: String, Hashable {
        case ctcss
        case dcs
        case none
    }

    struct Mention: Hashable {
        let kind: Kind
        let value: Double?
        let direction: Direction?
        let raw: String
    }

    enum Direction: String, Hashable {
        case rx
        case tx
    }

    private static let noToneRE = try? NSRegularExpression(
        pattern: "(?i)\\b(?:no|without)\\s+(?:ctcss|pl|tone)\\b|\\bcarrier\\s+squelch\\b|\\bcsq\\b"
    )

    // Common free-form formats:
    // - "CTCSS 67.0 Hz" / "CTCSS 67.0Hz" / "CTCSS: 67.0"
    // - "(PL 88.5Hz)" / "67.0 PL" / "PL=88.5"
    // - "Tone 67.0" / "Tone: 67.0 Hz"
    private static let ctcssREs: [NSRegularExpression] = [
        try? NSRegularExpression(pattern: "(?i)\\bctcss\\b\\s*[:=]?\\s*([0-9]{2,3}(?:\\.[0-9])?)\\s*(?:hz)?"),
        try? NSRegularExpression(pattern: "(?i)\\bpl\\b\\s*[:=]?\\s*([0-9]{2,3}(?:\\.[0-9])?)\\s*(?:hz)?"),
        try? NSRegularExpression(pattern: "(?i)\\btone\\b\\s*[:=]?\\s*([0-9]{2,3}(?:\\.[0-9])?)\\s*(?:hz)?"),
        try? NSRegularExpression(pattern: "(?i)\\b([0-9]{2,3}(?:\\.[0-9])?)\\s*(?:hz)?\\s*pl\\b")
    ].compactMap { $0 }

    private static let dcsREs: [NSRegularExpression] = [
        try? NSRegularExpression(pattern: "(?i)\\bdcs\\b\\s*[:=]?\\s*([0-9]{2,4})\\b"),
        try? NSRegularExpression(pattern: "(?i)\\b([0-9]{2,4})\\s*dcs\\b")
    ].compactMap { $0 }

    static func parseMentions(_ text: String) -> [Mention] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let ns = trimmed as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        var mentions: [Mention] = []

        if let noToneRE, noToneRE.firstMatch(in: trimmed, range: fullRange) != nil {
            mentions.append(Mention(kind: .none, value: nil, direction: nil, raw: "no/without tone"))
        }

        for re in ctcssREs {
            for m in re.matches(in: trimmed, range: fullRange) {
                guard m.numberOfRanges >= 2 else { continue }
                let raw = ns.substring(with: m.range(at: 0))
                let s = ns.substring(with: m.range(at: 1))
                guard let v = Double(s) else { continue }
                mentions.append(Mention(kind: .ctcss, value: v, direction: classifyDirection(text: trimmed, matchRange: m.range(at: 0)), raw: raw))
            }
        }

        for re in dcsREs {
            for m in re.matches(in: trimmed, range: fullRange) {
                guard m.numberOfRanges >= 2 else { continue }
                let raw = ns.substring(with: m.range(at: 0))

                 // Some SatNOGS descriptions contain modulation strings like "A-DCS".
                 // Treat those as non-squelch mentions.
                 let rawLC = raw.lowercased()
                 if rawLC.contains("a-dcs") || rawLC.contains("a dcs") {
                     continue
                 }

                let s = ns.substring(with: m.range(at: 1))
                guard let v = Double(s) else { continue }
                mentions.append(Mention(kind: .dcs, value: v, direction: classifyDirection(text: trimmed, matchRange: m.range(at: 0)), raw: raw))
            }
        }

        // De-dupe while preserving order.
        var seen = Set<Mention>()
        var out: [Mention] = []
        out.reserveCapacity(mentions.count)
        for m in mentions {
            if seen.contains(m) { continue }
            seen.insert(m)
            out.append(m)
        }
        return out
    }

    static func parseCTCSSHz(_ text: String) -> Double? {
        let mentions = parseMentions(text)
        if mentions.contains(where: { $0.kind == .none }) { return nil }
        return mentions.first(where: { $0.kind == .ctcss })?.value
    }

    static func guessRxTxCTCSSHz(_ text: String) -> (rx: Double?, tx: Double?) {
        let mentions = parseMentions(text)
        if mentions.contains(where: { $0.kind == .none }) { return (nil, nil) }

        var rx: Double?
        var tx: Double?

        for m in mentions where m.kind == .ctcss {
            guard let v = m.value else { continue }
            switch m.direction {
            case .rx:
                rx = rx ?? v
            case .tx:
                tx = tx ?? v
            case nil:
                break
            }
        }

        if rx == nil && tx == nil {
            if let v = mentions.first(where: { $0.kind == .ctcss })?.value {
                let lc = text.lowercased()
                if lc.contains("downlink") || lc.contains(" dl ") || lc.contains("dl:") {
                    rx = v
                } else {
                    tx = v
                }
            }
        }

        return (rx, tx)
    }

    private static func classifyDirection(text: String, matchRange: NSRange) -> Direction? {
        // Cheap heuristic: look at a small window around the match.
        let ns = text as NSString
        let start = max(0, matchRange.location - 30)
        let end = min(ns.length, matchRange.location + matchRange.length + 30)
        let window = ns.substring(with: NSRange(location: start, length: end - start)).lowercased()

        if window.range(of: "uplink") != nil || window.range(of: "transmit") != nil {
            return .tx
        }
        if window.range(of: "downlink") != nil || window.range(of: "receive") != nil {
            return .rx
        }

        if let re = try? NSRegularExpression(pattern: "(?i)\\b(ul|tx)\\b") {
            if re.firstMatch(in: window, range: NSRange(location: 0, length: (window as NSString).length)) != nil {
                return .tx
            }
        }
        if let re = try? NSRegularExpression(pattern: "(?i)\\b(dl|rx)\\b") {
            if re.firstMatch(in: window, range: NSRange(location: 0, length: (window as NSString).length)) != nil {
                return .rx
            }
        }
        return nil
    }
}
