//
//  AIChannelImporter.swift
//  FieldHT
//
//  Created by Benjamin Faershtein on 4/1/26.
//

import Foundation
import FoundationModels
import PDFKit

// MARK: - Generable Structs

@Generable(description: "A single ham radio channel entry")
struct ParsedChannel {
    // Frequencies first — generated first so they anchor everything that follows.
    @Guide(description: "Channel name, 10 characters max")
    var name: String

    @Guide(description: "Receive (output/downlink) frequency in MHz, e.g. 146.520", .range(50.0...1300.0))
    var rxFreqMHz: Double

    @Guide(description: "TX offset from RX in MHz. Use 0.0 for simplex. Typical values: +0.600 (VHF 2m), +1.600 (1.25m), +5.000 (UHF 70cm), +12.000 (23cm), +25.000 (33cm). Negative if TX is below RX.", .range(-30.0...30.0))
    var txOffsetMHz: Double

    // Booleans next — simple, unambiguous.
    @Guide(description: "True for narrow band 12.5 kHz NFM, false for wide band 25 kHz FM")
    var narrowBand: Bool

    @Guide(description: "True only if explicitly marked receive-only or monitor-only")
    var rxOnly: Bool

    // Tones last — generated after frequencies are already committed, with hard range constraint.
    // .range() uses token-masking: values outside 0.0–254.1 cannot be generated.
    @Guide(description: "TX CTCSS/PL squelch tone in Hz, e.g. 100.0. Use 0.0 if no tone.", .range(0.0...254.1))
    var txToneHz: Double

    @Guide(description: "RX CTCSS/PL squelch tone in Hz. Use 0.0 if no tone.", .range(0.0...254.1))
    var rxToneHz: Double
}

@Generable(description: "A list of parsed ham radio channels")
struct ParsedChannelList {
    @Guide(description: "All radio channels found, max 30")
    var channels: [ParsedChannel]
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

        statusUpdate("Analyzing with Apple Intelligence\u{2026}")

        // instructions: sets persistent parsing rules for this session.
        // Per WWDC guidance, put semantic rules here — not in the prompt.
        let session = LanguageModelSession(
            instructions: """
            You are a ham radio channel list parser.

            FREQUENCIES (rxFreqMHz / txFreqMHz):
            - Always in MHz, e.g. 146.520 or 447.000. Always ≥ 50.0.

            CTCSS / PL TONES (txToneHz / rxToneHz):
            - Small numbers between 67 and 254, representing Hz, e.g. 100.0 or 151.4.
            - In source documents these appear under column headers or labels such as:
              "PL", "CTCSS", "Tone", "T-SQL", "TSQL", "Encode", "Decode",
              "TX Tone", "RX Tone", "Squelch Tone", "Sub-tone", or just a bare number
              in a tone column (e.g. 100.0, 127.3, 88.5).
            - If a tone is listed, write it into txToneHz and/or rxToneHz.
            - If no tone is listed for that channel, use 0.0.

            TX OFFSET RULES (txOffsetMHz = txFreq − rxFreq):
            - Simplex: 0.0
            - Document lists explicit TX frequency: txOffsetMHz = txFreq − rxFreq
            - Document lists an offset (e.g. "+0.6", "–5.0"): use it directly
            - No TX info given, infer from band:
              VHF 144–148 MHz → +0.600
              1.25 m 222–225 MHz → +1.600
              UHF 440–450 MHz → +5.000
              33 cm 902–928 MHz → +25.000
              23 cm 1240–1300 MHz → +12.000
              All other bands → 0.0
            """
        )

        // prompt: just the task + raw document. The schema handles format.
        let prompt = """
        Extract all ham radio channels from the document below.
        Only include entries with valid amateur frequencies (50–1300 MHz).
        Skip headers, notes, and non-channel lines. Maximum 30 channels.

        Document:
        \(text.prefix(6000))
        """

        let response = try await session.respond(to: prompt, generating: ParsedChannelList.self)

        statusUpdate("Processing results\u{2026}")

        print("[AIImport] Model returned \(response.content.channels.count) raw channel(s)")
        for (i, p) in response.content.channels.enumerated() {
            print("[AIImport][\(i)] name=\(p.name) rx=\(p.rxFreqMHz) offset=\(p.txOffsetMHz) txTone=\(p.txToneHz) rxTone=\(p.rxToneHz) narrow=\(p.narrowBand) rxOnly=\(p.rxOnly)")
        }

        let channels: [Channel] = response.content.channels.enumerated().compactMap { index, parsed in
            let rxFreq = parsed.rxFreqMHz
            guard (50.0...1300.0).contains(rxFreq) else {
                print("[AIImport][\(index)] DROPPED — rxFreq \(rxFreq) out of range")
                return nil
            }

            // If the model found an explicit non-zero offset in the document, use it.
            // If offset is 0 (model saw no explicit TX info), infer from band so repeaters
            // get the correct uplink frequency instead of a simplex copy of RX.
            let txFreq: Double
            if parsed.txOffsetMHz != 0.0 {
                let computed = rxFreq + parsed.txOffsetMHz
                if (50.0...1300.0).contains(computed) {
                    txFreq = computed
                } else {
                    let inferred = Self.inferTxFreq(fromRx: rxFreq)
                    print("[AIImport][\(index)] computed tx \(computed) out of range — inferred \(inferred)")
                    txFreq = inferred
                }
            } else {
                txFreq = Self.inferTxFreq(fromRx: rxFreq)
                print("[AIImport][\(index)] offset=0 — inferred tx \(txFreq) from band")
            }

            // txToneHz / rxToneHz have a hard .range(0.0...254.1) token-masking constraint.
            // If only one tone is present (single-column doc), mirror it to the other.
            let effectiveTxTone = parsed.txToneHz > 0 ? parsed.txToneHz : parsed.rxToneHz
            let effectiveRxTone = parsed.rxToneHz > 0 ? parsed.rxToneHz : parsed.txToneHz
            let txSubAudio: SubAudio? = effectiveTxTone > 0 ? .frequency(effectiveTxTone) : nil
            let rxSubAudio: SubAudio? = effectiveRxTone > 0 ? .frequency(effectiveRxTone) : nil
            print("[AIImport][\(index)] final → rx=\(rxFreq) tx=\(txFreq) offset=\(parsed.txOffsetMHz) txTone=\(effectiveTxTone) rxTone=\(effectiveRxTone)")

            return Channel(
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
                bandwidth: parsed.narrowBand ? .narrow : .wide,
                preDeEmphBypass: false,
                sign: false,
                txAtMedPower: false,
                txDisable: parsed.rxOnly,
                fixedFreq: false,
                fixedBandwidth: false,
                fixedTxPower: false,
                mute: false,
                name: String(parsed.name.prefix(10))
            )
        }

        guard !channels.isEmpty else {
            throw AIImportError.noChannelsFound
        }

        return channels
    }

    // MARK: - Frequency Helpers

    /// Infers the standard TX (uplink) frequency from a repeater's RX (output) frequency.
    /// Returns rxFreq unchanged for simplex bands or unrecognised frequencies.
    private static func inferTxFreq(fromRx rx: Double) -> Double {
        switch rx {
        case 144.0..<148.0: return rx + 0.600   // 2 m repeater input
        case 222.0..<225.0: return rx + 1.600   // 1.25 m repeater input
        case 440.0..<450.0: return rx + 5.000   // 70 cm repeater input
        case 902.0..<928.0: return rx + 25.000  // 33 cm repeater input
        case 1240.0..<1300.0: return rx + 12.000 // 23 cm repeater input
        default:            return rx            // simplex / unknown → use RX
        }
    }

    // MARK: - Text Extraction

    private static func extractText(from url: URL) throws -> String {
        if url.pathExtension.lowercased() == "pdf" {
            return try extractPDFText(from: url)
        }

        // Try UTF-8 first, fall back to ISO Latin 1
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        if let text = try? String(contentsOf: url, encoding: .isoLatin1) {
            return text
        }

        throw AIImportError.cannotReadFile
    }

    private static func extractPDFText(from url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw AIImportError.cannotReadFile
        }

        var text = ""
        for pageIndex in 0..<document.pageCount {
            if let page = document.page(at: pageIndex),
               let pageText = page.string {
                text += pageText + "\n"
            }
        }

        guard !text.isEmpty else {
            throw AIImportError.cannotReadFile
        }

        return text
    }
}
