//
//  TipJarStore.swift
//  FieldHT
//

import Foundation
import Combine
import StoreKit

@MainActor
final class TipJarStore: ObservableObject {
    static let shared = TipJarStore()

    struct Tier: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let symbolName: String
    }

    static let tiers: [Tier] = [
        Tier(
            id: "com.fieldht.tip.small",
            title: "Small Tip",
            subtitle: "Help fund ongoing polish and bug fixes.",
            symbolName: "heart"
        ),
        Tier(
            id: "com.fieldht.tip.medium",
            title: "Medium Tip",
            subtitle: "Help cover testing gear and radio accessories.",
            symbolName: "heart.fill"
        ),
        Tier(
            id: "com.fieldht.tip.large",
            title: "Large Tip",
            subtitle: "Help fund new radio and speaker-mic support work.",
            symbolName: "star.fill"
        ),
    ]

    static let productIDs = tiers.map(\.id)

    @Published var statusMessage: String?

    private var didStart = false
    private var updatesTask: Task<Void, Never>?

    private init() {}

    deinit {
        updatesTask?.cancel()
    }

    func startIfNeeded() {
        guard !didStart else { return }
        didStart = true

        updatesTask = Task {
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else {
                    statusMessage = "The App Store could not verify this purchase."
                    continue
                }

                statusMessage = "Thanks for supporting FieldHT."
                await transaction.finish()
            }
        }
    }
}
