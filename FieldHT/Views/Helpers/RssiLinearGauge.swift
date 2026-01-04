//
//  RSSILinearGauge.swift
//  FieldHT
//
//  Created by Benjamin Faershtein on 12/14/25.
//

import SwiftUI

struct RSSILinearGauge: View {
    let rssi: Int   // 0 ... 100 (%)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Gauge(
                value: Double(rssi),
                in: 0...100
            ) {
                Text("RSSI")
            } currentValueLabel: {
                Text("\(rssi)%")
                    .monospacedDigit()
            }
            .gaugeStyle(.linearCapacity)
            .tint(rssiColor(for: rssi))
            .animation(.easeOut(duration: 0.2), value: rssi)

            HStack {
                Text("Weak")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Text("Strong")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Color helper
    private func rssiColor(for value: Int) -> Color {
        switch value {
        case 66...100: return .green
        case 33..<66: return .yellow
        default: return .red
        }
    }
}
