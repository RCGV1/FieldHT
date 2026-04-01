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

    @Guide(description: "Receive (output/downlink) frequency in MHz, e.g. 146.520")
    var rxFreqMHz: Double

    @Guide(description: "Transmit (input/uplink) frequency in MHz. For simplex equals rxFreqMHz. For repeaters apply the band offset.")
    var txFreqMHz: Double

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

            Channel frequencies are in MHz (megahertz), e.g. 146.520 or 447.000.
            CTCSS/PL tones are sub-audible squelch tones in Hz (hertz), e.g. 100.0 or 151.4. They are always between 67 and 254.
            These are completely different measurements. Never write a MHz frequency into a tone field.

            TX frequency rules:
            - Simplex: txFreqMHz = rxFreqMHz exactly.
            - Repeater with explicit TX freq or offset listed: apply it directly.
            - Repeater with no TX info, infer from band:
              VHF 144–148 MHz → txFreqMHz = rxFreqMHz + 0.600
              UHF 440–450 MHz → txFreqMHz = rxFreqMHz + 5.000
              1.2 GHz 1240–1300 MHz → txFreqMHz = rxFreqMHz + 12.000
              All other bands → txFreqMHz = rxFreqMHz
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

        let channels: [Channel] = response.content.channels.enumerated().compactMap { index, parsed in
            let rxFreq = parsed.rxFreqMHz
            guard (50.0...1300.0).contains(rxFreq) else { return nil }

            // Hard fallback: if model returned an invalid TX freq (0 or out of band),
            // infer it from the standard band offset rather than leaving it broken.
            let txFreq: Double
            if (50.0...1300.0).contains(parsed.txFreqMHz) {
                txFreq = parsed.txFreqMHz
            } else {
                txFreq = Self.inferTxFreq(fromRx: rxFreq)
            }

            // txToneHz / rxToneHz have a hard .range(0.0...254.1) token-masking constraint,
            // so invalid values cannot be generated. Still treat 0.0 as "no tone".
            let txSubAudio: SubAudio? = parsed.txToneHz > 0 ? .frequency(parsed.txToneHz) : nil
            let rxSubAudio: SubAudio? = parsed.rxToneHz > 0 ? .frequency(parsed.rxToneHz) : nil

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
