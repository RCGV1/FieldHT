//
//  AIChannelImporter.swift
//  FieldHT
//
//  Created by Benjamin Faershtein on 4/1/26.
//
//  Uses two separate AI sessions to avoid cross-field confusion:
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

    @Guide(description: "Transmit (input/uplink) frequency in MHz. Read directly from the document if listed. For repeaters with no explicit TX, apply the standard band offset (VHF +0.600, UHF +5.000, etc.). For simplex, use rxFreqMHz.", .range(50.0...1300.0))
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
    @Guide(description: "TX CTCSS/PL squelch tone in Hz, e.g. 100.0. Use 0.0 if no tone.", .range(0.0...254.1))
    var txToneHz: Double

    @Guide(description: "RX CTCSS/PL squelch tone in Hz. Use 0.0 if no tone.", .range(0.0...254.1))
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
            return "Apple Intelligence is not available on this device"
        case .cannotReadFile:
            return "Unable to read the selected file"
        case .noChannelsFound:
            return "No valid radio channels were found in the file"
        }
    }
}

// MARK: - Importer

enum AIChannelImporter {

    static func parse(url: URL, statusUpdate: @escaping @Sendable (String) -> Void) async throws -> [Channel] {
        statusUpdate("Reading file\u{2026}")
        let text = try extractText(from: url)

        guard SystemLanguageModel.default.isAvailable else {
            throw AIImportError.notAvailable
        }

        // MARK: Pass 1 — Frequencies
        statusUpdate("Extracting frequencies\u{2026}")

        let freqSession = LanguageModelSession(
            instructions: """
            You are a ham radio channel list parser focused on frequencies.
            Extract channel names and frequencies only — ignore any tone or squelch columns.

            Frequencies are always in MHz (e.g. 146.520, 447.000).

            TX frequency rules:
            - If the document lists an explicit TX frequency or offset, use it exactly.
            - For simplex channels (no repeater): txFreqMHz = rxFreqMHz.
            - For repeaters with no explicit TX info, infer from the standard band offset:
              VHF 144–148 MHz → txFreqMHz = rxFreqMHz + 0.600
              1.25 m 222–225 MHz → txFreqMHz = rxFreqMHz + 1.600
              UHF 440–450 MHz → txFreqMHz = rxFreqMHz + 5.000
              33 cm 902–928 MHz → txFreqMHz = rxFreqMHz + 25.000
              23 cm 1240–1300 MHz → txFreqMHz = rxFreqMHz + 12.000
            """
        )

        let freqPrompt = """
        Extract all ham radio channels from the document below.
        Only include entries with valid amateur frequencies (50–1300 MHz).
        Skip headers, notes, and non-channel lines. Maximum 30 channels.

        Document:
        \(text.prefix(6000))
        """

        let freqResponse = try await freqSession.respond(to: freqPrompt, generating: ParsedChannelFreqList.self)
        let parsedFreqs = freqResponse.content.channels

        print("[AIImport] Pass 1 — \(parsedFreqs.count) channel(s)")
        for (i, p) in parsedFreqs.enumerated() {
            print("[AIImport][P1][\(i)] name=\(p.name) rx=\(p.rxFreqMHz) tx=\(p.txFreqMHz) narrow=\(p.narrowBand) rxOnly=\(p.rxOnly)")
        }

        guard !parsedFreqs.isEmpty else { throw AIImportError.noChannelsFound }

        // MARK: Pass 2 — Tones
        statusUpdate("Extracting tones\u{2026}")

        let channelList = parsedFreqs.enumerated()
            .map { i, ch in "\(i). \(ch.name) (\(String(format: "%.3f", ch.rxFreqMHz)) MHz)" }
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
            """
        )

        let tonePrompt = """
        Find the TX and RX CTCSS/PL tone for each channel below.
        Return exactly \(parsedFreqs.count) entries in the same order.

        Channels:
        \(channelList)

        Document:
        \(text.prefix(6000))
        """

        let toneResponse = try await toneSession.respond(to: tonePrompt, generating: ParsedToneList.self)
        let parsedTones = toneResponse.content.tones

        print("[AIImport] Pass 2 — \(parsedTones.count) tone pair(s)")
        for (i, t) in parsedTones.enumerated() {
            print("[AIImport][P2][\(i)] txTone=\(t.txToneHz) rxTone=\(t.rxToneHz)")
        }

        // MARK: Merge & Build Channels
        statusUpdate("Processing results\u{2026}")

        var channels: [Channel] = []
        for (index, freq) in parsedFreqs.enumerated() {
            let rxFreq = freq.rxFreqMHz
            guard (50.0...1300.0).contains(rxFreq) else {
                print("[AIImport][\(index)] DROPPED — rxFreq \(rxFreq) out of range")
                continue
            }

            // Use model's TX directly; fall back to band inference only if invalid.
            let txFreq: Double
            let modelTx = freq.txFreqMHz.rounded3
            if (50.0...1300.0).contains(modelTx) {
                txFreq = modelTx
            } else {
                let inferred = Self.inferTxFreq(fromRx: rxFreq)
                print("[AIImport][\(index)] tx \(modelTx) invalid — inferred \(inferred)")
                txFreq = inferred
            }

            // Tone from pass 2, with index-safe fallback to no tone.
            let tone = index < parsedTones.count ? parsedTones[index] : ParsedTone(txToneHz: 0, rxToneHz: 0)
            // If only one of the tone fields is filled, mirror it to the other.
            let effectiveTxTone = tone.txToneHz > 0 ? tone.txToneHz : tone.rxToneHz
            let effectiveRxTone = tone.rxToneHz > 0 ? tone.rxToneHz : tone.txToneHz
            let txSubAudio: SubAudio? = effectiveTxTone > 0 ? .frequency(effectiveTxTone) : nil
            let rxSubAudio: SubAudio? = effectiveRxTone > 0 ? .frequency(effectiveRxTone) : nil

            print("[AIImport][\(index)] final → rx=\(rxFreq) tx=\(txFreq) txTone=\(effectiveTxTone) rxTone=\(effectiveRxTone)")

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

        // Deduplicate by RX frequency — keep entry with TX tone over one without.
        var seen: [String: Channel] = [:]
        var order: [String] = []
        for ch in channels {
            let key = String(format: "%.4f", ch.rxFreq)
            if let existing = seen[key] {
                if ch.txSubAudio != nil && existing.txSubAudio == nil { seen[key] = ch }
            } else {
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
        if dupeCount > 0 { print("[AIImport] Removed \(dupeCount) duplicate(s), \(deduped.count) channel(s) remain") }

        guard !deduped.isEmpty else { throw AIImportError.noChannelsFound }
        return deduped
    }

    // MARK: - TX Frequency Fallback
    // Only called when the model returns an invalid TX value.
    // Uses standard band offsets — no hardcoded specific frequencies.
    private static func inferTxFreq(fromRx rx: Double) -> Double {
        switch rx {
        case 144.0..<148.0:   return (rx + 0.600).rounded3
        case 222.0..<225.0:   return (rx + 1.600).rounded3
        case 440.0..<450.0:   return (rx + 5.000).rounded3
        case 902.0..<928.0:   return (rx + 25.000).rounded3
        case 1240.0..<1300.0: return (rx + 12.000).rounded3
        default:              return rx.rounded3
        }
    }

    // MARK: - Text Extraction

    private static func extractText(from url: URL) throws -> String {
        if url.pathExtension.lowercased() == "pdf" {
            return try extractPDFText(from: url)
        }
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        if let text = try? String(contentsOf: url, encoding: .isoLatin1) { return text }
        throw AIImportError.cannotReadFile
    }

    private static func extractPDFText(from url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else { throw AIImportError.cannotReadFile }
        var text = ""
        for pageIndex in 0..<document.pageCount {
            if let page = document.page(at: pageIndex), let pageText = page.string {
                text += pageText + "\n"
            }
        }
        guard !text.isEmpty else { throw AIImportError.cannotReadFile }
        return text
    }
}

// MARK: - Double rounding helper (3 decimal places = 1 kHz precision)
private extension Double {
    var rounded3: Double { (self * 1000).rounded() / 1000 }
}
