//
//  AIChannelImporter.swift
//  FieldHT
//
//  Created by Benjamin Faershtein on 4/1/26.
//
//  Imports channel data from structured documents when possible and falls back
//  to two AI passes for unstructured files:
//  Pass 1 — names + frequencies only (no tone context)
//  Pass 2 — CTCSS tones only (given channel list from pass 1)
//

import Foundation
import FoundationModels
import PDFKit

// MARK: - Pass 1: Frequencies

@Generable(description: "A single ham radio channel — name and frequencies only")
struct ParsedChannelFreq {
    @Guide(description: "Channel name, 10 characters max")
    var name: String

    @Guide(description: "Receive (output/downlink) frequency in MHz, e.g. 146.520", .range(50.0...1300.0))
    var rxFreqMHz: Double

    // Reasoning comes AFTER rxFreqMHz so the model has committed this channel's
    // specific RX value and can compute the correct per-channel TX from it.
    @Guide(description: "Given the rxFreqMHz above, state what TX frequency this specific channel uses. If the document lists a TX freq or offset, use it. Otherwise apply the band offset. Format: 'TX=<value> because <reason>'. E.g. 'TX=148.575 because VHF, 147.975+0.600'")
    var reasoning: String

    @Guide(description: "Transmit (input/uplink) frequency in MHz. Must match the value you computed in reasoning.", .range(50.0...1300.0))
    var txFreqMHz: Double

    @Guide(description: "True for narrow band 12.5 kHz NFM, false for wide 25 kHz FM")
    var narrowBand: Bool

    @Guide(description: "True only if explicitly marked receive-only or monitor-only")
    var rxOnly: Bool
}

@Generable(description: "List of parsed ham radio channels — frequencies only")
struct ParsedChannelFreqList {
    @Guide(description: "All channels found, max 30")
    var channels: [ParsedChannelFreq]
}

// MARK: - Pass 2: Tones

@Generable(description: "CTCSS/PL tone pair for one radio channel")
struct ParsedTone {
    // Reasoning first so the model identifies the correct tone before committing values.
    @Guide(description: "State the CTCSS/PL tone for this channel from the document. If the document shows one tone for this frequency, use it for both TX and RX. E.g. 'PL=107.2 for both' or 'No tone, CSQ'")
    var reasoning: String

    @Guide(description: "TX CTCSS/PL squelch tone in Hz, e.g. 100.0. Use 0.0 if no tone.", .range(0.0...254.1))
    var txToneHz: Double

    @Guide(description: "RX CTCSS/PL squelch tone in Hz. Must match txToneHz unless the document explicitly lists different encode and decode tones.", .range(0.0...254.1))
    var rxToneHz: Double
}

@Generable(description: "CTCSS/PL tones for a list of channels, one entry per channel in order")
struct ParsedToneList {
    @Guide(description: "One tone pair per channel, in the exact same order as the input channel list")
    var tones: [ParsedTone]
}

// MARK: - Errors

enum AIImportError: LocalizedError {
    case notAvailable
    case cannotReadFile
    case noChannelsFound

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "This file needs Apple Intelligence for document parsing on this device"
        case .cannotReadFile:
            return "Unable to read the selected file"
        case .noChannelsFound:
            return "No valid radio channels were found in the file"
        }
    }
}

// MARK: - Importer

enum AIChannelImporter {
    private static let maxModelInputCharacters = 1_800
    private static let maxModelPDFPages = 1
    private static let maxModelCSVLines = 40
    private static let maxModelTextLines = 60
    private static let modelInputRetryScales: [Double] = [1.0, 0.7, 0.45, 0.25, 0.12]

    static func parse(url: URL, statusUpdate: @escaping @Sendable (String) -> Void) async throws -> [Channel] {
        if url.pathExtension.lowercased() == "pdf" {
            statusUpdate("Reading file\u{2026}")
            statusUpdate("Parsing ICS-205 table\u{2026}")
            if let structuredChannels = try parseStructuredPDFChannels(from: url), !structuredChannels.isEmpty {
                print("[ChannelImport] Structured PDF parser produced \(structuredChannels.count) channel(s)")
                for (index, channel) in structuredChannels.enumerated() {
                    let txTone = channel.txSubAudio?.frequencyValue ?? 0
                    let rxTone = channel.rxSubAudio?.frequencyValue ?? 0
                    print("[ChannelImport][Structured][\(index)] name=\(channel.name) rx=\(channel.rxFreq) tx=\(channel.txFreq) txTone=\(txTone) rxTone=\(rxTone)")
                }
                return structuredChannels
            }
            print("[ChannelImport] Structured PDF parser returned no channels; falling back to model parsing")
        }

        guard SystemLanguageModel.default.isAvailable else {
            throw AIImportError.notAvailable
        }

        // MARK: Pass 1 — Frequencies
        statusUpdate("Extracting frequencies\u{2026}")

        let freqSession = LanguageModelSession(
            instructions: """
            You are a ham radio channel frequency extractor.
            Your ONLY job is to find RX and TX radio frequencies. Completely ignore tone, CTCSS, PL, and squelch columns.

            CRITICAL: txFreqMHz is a full amateur radio frequency in MHz.
            It must always be within 26 MHz of rxFreqMHz (the maximum standard ham repeater offset is 25 MHz).
            CTCSS/PL tones look like 67.0, 88.5, 94.8, 100.0, 107.2, 118.8, 127.3 — these are Hz values, NOT MHz frequencies. NEVER write them into txFreqMHz.

            WRONG: rxFreqMHz=147.315, txFreqMHz=118.8  ← 118.8 is a CTCSS tone, not a TX frequency
            RIGHT: rxFreqMHz=147.315, txFreqMHz=147.915  ← 147.315 + 0.600 band offset

            TX frequency rules (in order of priority):
            1. If the document lists an explicit TX frequency column: use that value.
            2. If the document lists an offset (e.g. "+0.6", "–5.0"): txFreqMHz = rxFreqMHz + offset.
            3. If no TX info in the document, infer from band:
               VHF 144–148 MHz → txFreqMHz = rxFreqMHz + 0.600
               1.25 m 222–225 MHz → txFreqMHz = rxFreqMHz + 1.600
               UHF 440–450 MHz → txFreqMHz = rxFreqMHz + 5.000
               33 cm 902–928 MHz → txFreqMHz = rxFreqMHz + 25.000
               23 cm 1240–1300 MHz → txFreqMHz = rxFreqMHz + 12.000
               Simplex / other bands → txFreqMHz = rxFreqMHz
            """
        )

        let parsedFreqs: [ParsedChannelFreq]
        do {
            let freqResponse: LanguageModelSession.Response<ParsedChannelFreqList> = try await respondWithRetry(
                session: freqSession,
                url: url,
                statusUpdate: statusUpdate
            ) { text in
                """
                Extract all ham radio channels from the document below.
                Only include entries with valid amateur frequencies (50–1300 MHz).
                Skip headers, notes, and non-channel lines. Maximum 30 channels.

                Document:
                \(text)
                """
            }
            parsedFreqs = freqResponse.content.channels
        } catch {
            print("[ChannelImport] Frequency extraction failed: \(error)")
            throw error
        }

        print("[ChannelImport][Model][P1] \(parsedFreqs.count) channel(s)")
        for (i, p) in parsedFreqs.enumerated() {
            print("[ChannelImport][Model][P1][\(i)] reasoning: \(p.reasoning)")
            print("[ChannelImport][Model][P1][\(i)] name=\(p.name) rx=\(p.rxFreqMHz) tx=\(p.txFreqMHz) narrow=\(p.narrowBand) rxOnly=\(p.rxOnly)")
        }

        guard !parsedFreqs.isEmpty else { throw AIImportError.noChannelsFound }

        // MARK: Pass 2 — Tones
        statusUpdate("Extracting tones\u{2026}")

        let channelList = parsedFreqs.enumerated()
            .map { i, ch in "\(i). \(ch.name) — RX \(String(format: "%.3f", ch.rxFreqMHz)) MHz" }
            .joined(separator: "\n")

        let toneSession = LanguageModelSession(
            instructions: """
            You are a ham radio CTCSS/PL tone extractor.
            CTCSS/PL tones are sub-audible squelch tones between 67 and 254 Hz
            (e.g. 88.5, 100.0, 107.2, 118.8, 127.3, 151.4).
            In documents they appear under labels such as:
            PL, CTCSS, Tone, T-SQL, TSQL, Encode, Decode, TX Tone, RX Tone, Sub-tone.
            Return exactly one tone pair per channel, in the same order as the channel list.
            Use 0.0 for channels with no tone (carrier squelch / CSQ / no tone listed).
            If multiple channels share the same RX frequency, use the channel name and nearby row text
            to keep their tones separate. Do not mix tones between adjacent rows.
            """
        )

        let parsedTones: [ParsedTone]
        do {
            let toneResponse: LanguageModelSession.Response<ParsedToneList> = try await respondWithRetry(
                session: toneSession,
                url: url,
                statusUpdate: statusUpdate
            ) { text in
                """
                Find the CTCSS/PL tone for each channel below. Match each channel by its RX frequency.
                Return exactly \(parsedFreqs.count) entries in the same order as the channel list.
                Use 0.0 for any channel with no tone (CSQ / carrier squelch).

                Channels:
                \(channelList)

                Document:
                \(text)
                """
            }
            parsedTones = toneResponse.content.tones
        } catch {
            print("[ChannelImport] Tone extraction failed: \(error)")
            throw error
        }

        print("[ChannelImport][Model][P2] \(parsedTones.count) tone pair(s)")
        for (i, t) in parsedTones.enumerated() {
            print("[ChannelImport][Model][P2][\(i)] reasoning: \(t.reasoning)")
            print("[ChannelImport][Model][P2][\(i)] txTone=\(t.txToneHz) rxTone=\(t.rxToneHz)")
        }

        // MARK: Merge & Build Channels
        statusUpdate("Processing results\u{2026}")

        var channels: [Channel] = []
        for (index, freq) in parsedFreqs.enumerated() {
            let rxFreq = freq.rxFreqMHz
            guard (50.0...1300.0).contains(rxFreq) else {
                print("[ChannelImport][Model][\(index)] DROPPED — rxFreq \(rxFreq) out of range")
                continue
            }

            // Use model's TX if it's a plausible radio frequency (within 30 MHz of RX).
            // If it looks like a CTCSS tone got written into the TX field, fall back to band inference.
            let txFreq: Double
            let modelTx = freq.txFreqMHz.rounded3
            let txRxDelta = abs(modelTx - rxFreq)
            let inferred = Self.inferTxFreq(fromRx: rxFreq)
            let standardOffset = Self.expectedStandardOffset(forRx: rxFreq)
            let invalidRepeaterDirection = standardOffset != nil && modelTx != rxFreq && modelTx < rxFreq
            if (50.0...1300.0).contains(modelTx) && txRxDelta <= 26.0 && !invalidRepeaterDirection {
                txFreq = modelTx
            } else {
                print("[ChannelImport][Model][\(index)] tx \(modelTx) rejected (delta=\(txRxDelta), negativeRepeaterDirection=\(invalidRepeaterDirection)) — inferred \(inferred)")
                txFreq = inferred
            }

            // Tone from pass 2, with index-safe fallback to no tone.
            let tone = index < parsedTones.count
                ? parsedTones[index]
                : ParsedTone(reasoning: "Missing tone response", txToneHz: 0, rxToneHz: 0)
            // If only one of the tone fields is filled, mirror it to the other.
            let effectiveTxTone = tone.txToneHz > 0 ? tone.txToneHz : tone.rxToneHz
            let effectiveRxTone = tone.rxToneHz > 0 ? tone.rxToneHz : tone.txToneHz
            let txSubAudio: SubAudio? = effectiveTxTone > 0 ? .frequency(effectiveTxTone) : nil
            let rxSubAudio: SubAudio? = effectiveRxTone > 0 ? .frequency(effectiveRxTone) : nil

            print("[ChannelImport][Model][\(index)] final → rx=\(rxFreq) tx=\(txFreq) txTone=\(effectiveTxTone) rxTone=\(effectiveRxTone)")

            channels.append(Channel(
                channelID: index,
                txMod: .fm,
                txFreq: txFreq,
                rxMod: .fm,
                rxFreq: rxFreq,
                txSubAudio: txSubAudio,
                rxSubAudio: rxSubAudio,
                scan: true,
                txAtMaxPower: true,
                talkAround: false,
                bandwidth: freq.narrowBand ? .narrow : .wide,
                preDeEmphBypass: false,
                sign: false,
                txAtMedPower: false,
                txDisable: freq.rxOnly,
                fixedFreq: false,
                fixedBandwidth: false,
                fixedTxPower: false,
                mute: false,
                name: String(freq.name.prefix(10))
            ))
        }

        // Deduplicate only exact matches. Real frequency plans can legitimately contain
        // multiple channels with the same RX but different names, TX values, or tones.
        var seen: [String: Channel] = [:]
        var order: [String] = []
        for ch in channels {
            let key = Self.dedupKey(for: ch)
            if seen[key] == nil {
                seen[key] = ch
                order.append(key)
            }
        }
        let deduped = order.enumerated().compactMap { i, key -> Channel? in
            guard var ch = seen[key] else { return nil }
            ch.channelID = i
            return ch
        }

        let dupeCount = channels.count - deduped.count
        if dupeCount > 0 { print("[ChannelImport] Removed \(dupeCount) duplicate(s), \(deduped.count) channel(s) remain") }

        guard !deduped.isEmpty else { throw AIImportError.noChannelsFound }
        return deduped
    }

    // MARK: - TX Frequency Fallback
    // Only called when the model returns an invalid TX value.
    // Uses standard band offsets — no hardcoded specific frequencies.
    private static func expectedStandardOffset(forRx rx: Double) -> Double? {
        switch rx {
        case 144.0..<148.0:   return 0.600
        case 222.0..<225.0:   return 1.600
        case 440.0..<450.0:   return 5.000
        case 902.0..<928.0:   return 25.000
        case 1240.0..<1300.0: return 12.000
        default:              return nil
        }
    }

    private static func inferTxFreq(fromRx rx: Double) -> Double {
        if let offset = expectedStandardOffset(forRx: rx) {
            return (rx + offset).rounded3
        }
        return rx.rounded3
    }

    private static func dedupKey(for channel: Channel) -> String {
        let txTone = channel.txSubAudio?.frequencyValue ?? 0
        let rxTone = channel.rxSubAudio?.frequencyValue ?? 0
        return [
            channel.name.uppercased(),
            String(format: "%.4f", channel.rxFreq),
            String(format: "%.4f", channel.txFreq),
            String(format: "%.1f", txTone),
            String(format: "%.1f", rxTone),
            channel.bandwidth.rawValue,
            channel.txMod.rawValue,
            channel.rxMod.rawValue
        ].joined(separator: "|")
    }

    // MARK: - Structured ICS-205 PDF Parsing

    private static func parseStructuredPDFChannels(from url: URL) throws -> [Channel]? {
        guard let document = PDFDocument(url: url) else { throw AIImportError.cannotReadFile }

        let selectionText = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.selection(for: document.page(at: $0)?.bounds(for: .mediaBox) ?? .zero)?.string }
            .joined(separator: "\n")

        guard selectionText.localizedCaseInsensitiveContains("ICS 205"),
              selectionText.contains("RX Freq"),
              selectionText.contains("TX Freq") else {
            return nil
        }

        let lines = selectionText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let blockStartRegex = try NSRegularExpression(
            pattern: #"^(\d+)\s+[A-Z][A-Z/\-]*(?:\s+.+)?$"#,
            options: [.caseInsensitive]
        )
        let blockParseRegex = try NSRegularExpression(
            pattern: #"^(\d+)\s+([A-Z][A-Z/\-]*)\s+(.+?)\s+(N/A|\d{3}\.\d{4,5})\s+(?:([NW])\s+)?(CSQ|N/A|\d{2,3}\.\d)\s+(N/A|\d{3}\.\d{4,5})\s+(?:([NW])\s+)?(CSQ|N/A|\d{2,3}\.\d)\s+([ADM])(?:\s+(.*))?$"#,
            options: [.caseInsensitive]
        )

        var blocks: [[String]] = []
        var currentBlock: [String] = []

        for line in lines {
            if line.contains("Prepared By") { break }
            if blockStartRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                if !currentBlock.isEmpty {
                    blocks.append(currentBlock)
                }
                currentBlock = [line]
            } else if !currentBlock.isEmpty {
                currentBlock.append(line)
            } else {
                continue
            }
        }
        if !currentBlock.isEmpty {
            blocks.append(currentBlock)
        }

        var parsedChannels: [Channel] = []
        for block in blocks {
            let normalized = block.joined(separator: " ").replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            guard let match = blockParseRegex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) else {
                continue
            }

            let channelNumber = Int(Self.capture(1, in: normalized, using: match)) ?? 0
            let rawNameSegment = Self.capture(3, in: normalized, using: match)
            let rxText = Self.capture(4, in: normalized, using: match)
            let rxNW = Self.capture(5, in: normalized, using: match)
            let rxToneText = Self.capture(6, in: normalized, using: match)
            let txText = Self.capture(7, in: normalized, using: match)
            let txNW = Self.capture(8, in: normalized, using: match)
            let txToneText = Self.capture(9, in: normalized, using: match)
            let modeText = Self.capture(10, in: normalized, using: match)

            // Skip blank separator rows and channels without actual frequencies.
            guard let rxFreq = Double(rxText), rxFreq >= 50 else {
                continue
            }
            let txDisable = txText.uppercased() == "N/A"
            let txFreq = Double(txText) ?? rxFreq

            let txTone = Self.parseTone(txToneText)
            let rxTone = Self.parseTone(rxToneText)
            let modulation: ModulationType = modeText == "D" ? .dmr : .fm
            let bandwidth: BandwidthType = (rxNW.uppercased() == "N" || txNW.uppercased() == "N") ? .narrow : .wide
            let name = Self.extractICS205Name(from: rawNameSegment, fallbackChannelNumber: channelNumber)

            parsedChannels.append(Channel(
                channelID: parsedChannels.count,
                txMod: modulation,
                txFreq: txFreq.rounded3,
                rxMod: modulation,
                rxFreq: rxFreq.rounded3,
                txSubAudio: txTone > 0 ? .frequency(txTone) : nil,
                rxSubAudio: rxTone > 0 ? .frequency(rxTone) : nil,
                scan: true,
                txAtMaxPower: true,
                talkAround: false,
                bandwidth: bandwidth,
                preDeEmphBypass: false,
                sign: false,
                txAtMedPower: false,
                txDisable: txDisable,
                fixedFreq: false,
                fixedBandwidth: false,
                fixedTxPower: false,
                mute: false,
                name: String(name.prefix(10))
            ))
        }

        return parsedChannels.isEmpty ? nil : parsedChannels
    }

    private static func extractICS205Name(from rawSegment: String, fallbackChannelNumber: Int) -> String {
        let assignmentMarkers = ["HAM TEAM", "FORT ORD", "CARMEL VLY", "SKI / HAM", "& TALK IN", "Automatic Packet", "Reporting System"]
        var candidate = rawSegment
        for marker in assignmentMarkers {
            if let range = candidate.range(of: marker) {
                candidate = String(candidate[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }

        let tokens = candidate
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }

        if let first = tokens.first {
            return first
        }
        return "CH\(fallbackChannelNumber)"
    }

    private static func parseTone(_ text: String) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return 0
        }
        let normalized = trimmed.uppercased()
        if normalized == "CSQ" || normalized == "N/A" {
            return 0
        }
        return Double(trimmed) ?? 0
    }

    private static func capture(_ index: Int, in line: String, using match: NSTextCheckingResult) -> String {
        guard let range = Range(match.range(at: index), in: line) else { return "" }
        return String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Text Extraction

    private static func respondWithRetry<T: Generable>(
        session: LanguageModelSession,
        url: URL,
        statusUpdate: @escaping @Sendable (String) -> Void,
        promptBuilder: (String) -> String
    ) async throws -> LanguageModelSession.Response<T> {
        var lastError: Error?

        for (index, scale) in modelInputRetryScales.enumerated() {
            let text = try extractModelInput(from: url, scale: scale)
            let scalePercent = Int((scale * 100).rounded())
            if index > 0 {
                statusUpdate("Retrying with a smaller document excerpt (\(scalePercent)%)\u{2026}")
            }

            do {
                return try await session.respond(
                    to: promptBuilder(text),
                    generating: T.self,
                    options: GenerationOptions(sampling: .greedy)
                )
            } catch {
                lastError = error
                if isContextWindowError(error) {
                    print("[ChannelImport] Model context exceeded at \(scalePercent)% input; retrying smaller excerpt")
                    continue
                }
                throw error
            }
        }

        throw lastError ?? AIImportError.cannotReadFile
    }

    private static func isContextWindowError(_ error: Error) -> Bool {
        let message = String(describing: error).lowercased()
        return message.contains("exceededcontextwindowsize")
            || message.contains("context window")
            || message.contains("context size")
    }

    private static func extractModelInput(from url: URL, scale: Double = 1.0) throws -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return try extractPDFPreviewForModel(from: url, scale: scale)
        case "csv":
            return try extractDelimitedPreview(
                from: url,
                maxLines: scaledCount(maxModelCSVLines, scale: scale),
                charLimit: scaledCount(maxModelInputCharacters, scale: scale)
            )
        default:
            return try extractPlainTextPreview(
                from: url,
                maxLines: scaledCount(maxModelTextLines, scale: scale),
                charLimit: scaledCount(maxModelInputCharacters, scale: scale)
            )
        }
    }

    private static func extractPDFPreviewForModel(from url: URL, scale: Double) throws -> String {
        guard let document = PDFDocument(url: url) else { throw AIImportError.cannotReadFile }
        var text = ""
        let pageCount = min(document.pageCount, scaledCount(maxModelPDFPages, scale: scale))
        let charLimit = scaledCount(maxModelInputCharacters, scale: scale)
        for pageIndex in 0..<pageCount {
            if let page = document.page(at: pageIndex), let pageText = page.string, !pageText.isEmpty {
                text += "\n--- Page \(pageIndex + 1) ---\n"
                text += pageText + "\n"
            }
            if text.count >= charLimit {
                break
            }
        }
        guard !text.isEmpty else { throw AIImportError.cannotReadFile }
        if document.pageCount > pageCount || text.count > charLimit {
            print("[ChannelImport] Model input truncated to first \(pageCount) PDF page(s)")
        }
        return String(text.prefix(charLimit))
    }

    private static func extractDelimitedPreview(from url: URL, maxLines: Int, charLimit: Int) throws -> String {
        let text = try readPlainText(from: url)
        let lines = text.components(separatedBy: .newlines)
        let preview = lines.prefix(maxLines).joined(separator: "\n")
        if lines.count > maxLines || preview.count > charLimit {
            print("[ChannelImport] Model input truncated to first \(maxLines) delimited rows")
        }
        return String(preview.prefix(charLimit))
    }

    private static func extractPlainTextPreview(from url: URL, maxLines: Int, charLimit: Int) throws -> String {
        let text = try readPlainText(from: url)
        let lines = text.components(separatedBy: .newlines)
        let preview = lines.prefix(maxLines).joined(separator: "\n")
        if lines.count > maxLines || preview.count > charLimit {
            print("[ChannelImport] Model input truncated to first \(maxLines) text lines")
        }
        return String(preview.prefix(charLimit))
    }

    private static func scaledCount(_ base: Int, scale: Double) -> Int {
        max(1, Int((Double(base) * scale).rounded(.down)))
    }

    private static func readPlainText(from url: URL) throws -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        if let text = try? String(contentsOf: url, encoding: .isoLatin1) { return text }
        throw AIImportError.cannotReadFile
    }
}

// MARK: - Double rounding helper (3 decimal places = 1 kHz precision)
private extension Double {
    var rounded3: Double { (self * 1000).rounded() / 1000 }
}

private extension SubAudio {
    var frequencyValue: Double? {
        switch self {
        case .frequency(let value):
            return value
        case .dcs:
            return nil
        }
    }
}
