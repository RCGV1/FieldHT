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
    @Guide(description: "Channel name, max 10 characters")
    var name: String

    @Guide(description: "Receive frequency in MHz, e.g. 146.520")
    var rxFreqMHz: Double

    @Guide(description: "Transmit frequency in MHz. Same as rxFreqMHz for simplex.")
    var txFreqMHz: Double

    @Guide(description: "TX CTCSS/PL tone in Hz, e.g. 100.0. Use 0.0 if none.")
    var txCtcssHz: Double

    @Guide(description: "RX CTCSS/PL tone in Hz. Use 0.0 if none.")
    var rxCtcssHz: Double

    @Guide(description: "true for 12.5 kHz NFM, false for 25 kHz FM")
    var narrowBand: Bool

    @Guide(description: "true if receive-only (no transmit)")
    var rxOnly: Bool
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

        let session = LanguageModelSession(
            instructions: "You are a ham radio channel list parser. Extract channel data precisely from the provided text."
        )

        let prompt = """
        Extract all ham radio repeater and channel entries from the document below.

        For each channel:
        - name: short label \u{2264}10 chars (abbreviate if needed)
        - rxFreqMHz: receive/downlink frequency in MHz (e.g. 146.520)
        - txFreqMHz: transmit/uplink frequency. For repeaters without explicit TX freq, calculate it using standard offsets: +0.600 MHz for VHF (144\u{2013}148 MHz), \u{2013}0.600 MHz for some, +5.000 MHz for UHF (440\u{2013}450 MHz). For simplex, same as rxFreqMHz.
        - txCtcssHz: TX CTCSS/PL tone in Hz if listed (e.g. 100.0), else 0.0
        - rxCtcssHz: RX CTCSS/PL tone in Hz if listed, else 0.0
        - narrowBand: true for NFM/12.5 kHz, false for FM/25 kHz (default false)
        - rxOnly: true only if explicitly marked as receive-only or monitor

        Only include entries with valid amateur radio frequencies (50\u{2013}1300 MHz).
        Skip header rows, totals, notes, and non-channel lines.
        Max 30 channels.

        Document:
        \(text.prefix(6000))
        """

        let response = try await session.respond(to: prompt, generating: ParsedChannelList.self)

        statusUpdate("Processing results\u{2026}")

        let channels: [Channel] = response.content.channels.enumerated().compactMap { index, parsed in
            guard (50...1300).contains(parsed.rxFreqMHz) else { return nil }

            let txSubAudio: SubAudio? = parsed.txCtcssHz > 0 ? .frequency(parsed.txCtcssHz) : nil
            let rxSubAudio: SubAudio? = parsed.rxCtcssHz > 0 ? .frequency(parsed.rxCtcssHz) : nil

            return Channel(
                channelID: index,
                txMod: .fm,
                txFreq: parsed.txFreqMHz,
                rxMod: .fm,
                rxFreq: parsed.rxFreqMHz,
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
