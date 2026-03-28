//
//  APRSSymbolPicker.swift
//  FieldHT
//

import SwiftUI

// MARK: - Row shown in the form (taps to open the picker sheet)

struct APRSSymbolRow: View {
    let selectedCode: String
    let onSelect: (APRSSymbol) -> Void

    @State private var showingPicker = false

    private var selectedSymbol: APRSSymbol? {
        APRSSymbol.symbol(for: selectedCode)
    }

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            HStack(spacing: 12) {
                Text("Symbol")
                    .foregroundColor(.primary)
                Spacer()
                if let sym = selectedSymbol {
                    APRSSymbolImage(tocall: sym.tocall, size: 28)
                    Text(sym.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if !selectedCode.isEmpty {
                    Text(selectedCode)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.secondary)
                } else {
                    Text("Choose…")
                        .foregroundColor(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showingPicker) {
            APRSSymbolPickerSheet(selectedCode: selectedCode, onSelect: { sym in
                onSelect(sym)
                showingPicker = false
            })
        }
    }
}

// MARK: - Picker sheet

private struct APRSSymbolPickerSheet: View {
    let selectedCode: String
    let onSelect: (APRSSymbol) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [APRSSymbol] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return APRSSymbol.all }
        return APRSSymbol.all.filter {
            $0.description.lowercased().contains(q) || $0.code.contains(q)
        }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 8)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filtered) { sym in
                        APRSSymbolCell(
                            symbol: sym,
                            isSelected: sym.code == selectedCode
                        ) {
                            onSelect(sym)
                        }
                    }
                }
                .padding()
            }
            .searchable(text: $searchText, prompt: "Search symbols")
            .navigationTitle("APRS Symbol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Individual cell

private struct APRSSymbolCell: View {
    let symbol: APRSSymbol
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                APRSSymbolImage(tocall: symbol.tocall, size: 44)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                Text(symbol.description)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Image loader

struct APRSSymbolImage: View {
    let tocall: String
    let size: CGFloat

    var body: some View {
        if let path = Bundle.main.path(forResource: tocall, ofType: "png"),
           let uiImage = UIImage(contentsOfFile: path) {
            Image(uiImage: uiImage)
                .resizable()
                .interpolation(.medium)
                .frame(width: size, height: size)
        } else {
            // Fallback: show the tocall code as text
            Text(tocall)
                .font(.system(size: size * 0.3, design: .monospaced))
                .frame(width: size, height: size)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(4)
        }
    }
}
