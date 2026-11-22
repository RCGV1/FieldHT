//
//  AIImportPreviewSheet.swift
//  FieldHT
//
//  Created by Benjamin Faershtein on 4/1/26.
//

import SwiftUI

struct AIImportPreviewSheet: View {
    let channels: [Channel]
    let onImport: ([Channel]) -> Void
    var frequencyRanges: DeviceFrequencyRanges? = nil

    private var compatibleChannels: [Channel] {
        channels.filter { ChannelFrequencyValidator.issues(for: $0, ranges: frequencyRanges).isEmpty }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var detailLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(
                        "Found \(channels.count) channel\(channels.count == 1 ? "" : "s") in this file",
                        systemImage: "doc.text.magnifyingglass"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if compatibleChannels.count < channels.count {
                        Text("Channels with unsupported frequencies are excluded from this import.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Channels") {
                    ForEach(Array(channels.enumerated()), id: \.offset) { _, channel in
                        let issues = ChannelFrequencyValidator.issues(for: channel, ranges: frequencyRanges)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(channel.name.isEmpty ? "Unnamed" : channel.name)
                                .font(.headline)

                            detailLayout {
                                Text(String(format: "RX %.4f", channel.rxFreq))
                                    .font(.subheadline)
                                    .monospacedDigit()

                                if channel.txFreq != channel.rxFreq {
                                    Text(String(format: "TX %.4f", channel.txFreq))
                                        .font(.subheadline)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }

                            detailLayout {
                                if let tone = channel.txSubAudio, case .frequency(let hz) = tone {
                                    Text(String(format: "Tone %.1f", hz))
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }

                                Text(channel.bandwidth == .narrow ? "NFM" : "FM")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(channel.bandwidth == .narrow ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                                    )

                                if channel.txDisable {
                                    Text("RX Only")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                            ForEach(issues, id: \.self) {
                                Label($0, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .navigationTitle("Import Preview")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(compatibleChannels.count)") {
                        dismiss()
                        onImport(compatibleChannels)
                    }
                    .fontWeight(.semibold)
                    .disabled(compatibleChannels.isEmpty)
                }
            }
        }
    }
}
