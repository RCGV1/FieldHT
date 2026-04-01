//
//  RadioIntentBridge.swift
//  FieldHT
//
//  Singleton that App Intents use to reach the live RadioManager.
//  FieldHTApp sets `RadioIntentBridge.shared.manager` on launch.
//  Intents call `requireConnected()` which throws RadioNotConnectedError
//  when the radio is not connected via Bluetooth.
//

import Foundation
import AppIntents

// MARK: - Error

struct RadioNotConnectedError: LocalizedError {
    var errorDescription: String? {
        "No radio connected. Open FieldHT and connect to your radio first."
    }
    var failureReason: String? {
        "The radio is not connected via Bluetooth."
    }
    var recoverySuggestion: String? {
        "Open FieldHT, go to the Connect tab, and pair your radio."
    }
}

// MARK: - Bridge

/// Thread-safe bridge between App Intents and the live RadioManager.
/// All access must happen on the main actor because RadioManager is @MainActor.
@MainActor
final class RadioIntentBridge {
    static let shared = RadioIntentBridge()
    private init() {}

    var manager: RadioManager?

    /// Returns the connected manager or throws RadioNotConnectedError.
    func requireConnected() throws -> RadioManager {
        guard let m = manager, m.isConnected else {
            throw RadioNotConnectedError()
        }
        return m
    }
}
