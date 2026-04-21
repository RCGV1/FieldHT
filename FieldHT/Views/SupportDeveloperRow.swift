//
//  SupportDeveloperRow.swift
//  FieldHT
//
//  In-app tip tiers for use inside SwiftUI forms and support cards.
//

import SwiftUI
import StoreKit

struct SupportDeveloperRow: View {
    @StateObject private var tipStore = TipJarStore.shared
    @State private var isPresentingTipStore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                isPresentingTipStore = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.pink.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Support FieldHT")
                            .foregroundStyle(.primary)
                        Text("Open the tip picker to choose an amount.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .contentShape(Rectangle())

            if let statusMessage = tipStore.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            tipStore.startIfNeeded()
        }
        .sheet(isPresented: $isPresentingTipStore) {
            NavigationStack {
                TipStoreSheet()
            }
        }
    }
}

private struct TipStoreSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        StoreView(ids: TipJarStore.productIDs, prefersPromotionalIcon: false)
            .navigationTitle("Support FieldHT")
            .navigationBarTitleDisplayMode(.inline)
            .productViewStyle(.compact)
            .storeButton(.visible, for: .restorePurchases)
            .padding()
            .safeAreaInset(edge: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose a tip tier")
                        .font(.headline)
                    Text("Tips are optional and help fund testing hardware, compatibility work, and support for more radios and speaker mics.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
}

#Preview {
    Form {
        Section("Support") {
            SupportDeveloperRow()
        }
    }
}
