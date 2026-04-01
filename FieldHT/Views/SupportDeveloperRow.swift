//
//  SupportDeveloperRow.swift
//  FieldHT
//
//  A tasteful "Buy me a coffee" row for use inside a SwiftUI Form.
//

import SwiftUI

struct SupportDeveloperRow: View {
    private let url = URL(string: "https://buymeacoffee.com/benfaer")!

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 14) {
                // Icon styled like an iOS app icon — BMC yellow
                Image(systemName: "cup.and.heat.waves.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.75))
                    .frame(width: 32, height: 32)
                    .background(Color(red: 1.0, green: 0.85, blue: 0.0))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Buy Me a Coffee")
                        .foregroundStyle(.primary)
                    Text("Enjoying FieldHT? Support its development")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    Form {
        Section("Support") {
            SupportDeveloperRow()
        }
    }
}
