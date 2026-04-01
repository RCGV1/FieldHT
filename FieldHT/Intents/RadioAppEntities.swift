//
//  RadioAppEntities.swift
//  FieldHT
//
//  AppEntity types for zones and channels used as Siri/Shortcuts intent parameters.
//

import AppIntents
import Foundation

// MARK: - Zone Entity

struct ZoneEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Zone")
    static var defaultQuery = ZoneQuery()

    /// String-encoded zone index (e.g. "0", "1").
    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }

    var zoneIndex: Int { Int(id) ?? 0 }
}

struct ZoneQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ZoneEntity] {
        let names = await MainActor.run {
            RadioIntentBridge.shared.manager?.regionNames ?? []
        }
        return identifiers.compactMap { id in
            guard let index = Int(id), index < names.count else { return nil }
            return ZoneEntity(id: id, name: names[index])
        }
    }

    func suggestedEntities() async throws -> [ZoneEntity] {
        let names = await MainActor.run {
            RadioIntentBridge.shared.manager?.regionNames ?? []
        }
        return names.enumerated().map { ZoneEntity(id: String($0.offset), name: $0.element) }
    }

    /// Resolves a spoken or typed string (e.g. "ARES") to matching zones.
    func entities(matching string: String) async throws -> [ZoneEntity] {
        let names = await MainActor.run {
            RadioIntentBridge.shared.manager?.regionNames ?? []
        }
        let query = string.lowercased()
        return names.enumerated()
            .filter { $0.element.lowercased().contains(query) }
            .map { ZoneEntity(id: String($0.offset), name: $0.element) }
    }
}

// MARK: - Channel Entity

struct ChannelEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Channel")
    static var defaultQuery = ChannelQuery()

    /// String-encoded channelID.
    var id: String
    var name: String
    var frequency: Double

    var displayRepresentation: DisplayRepresentation {
        let freqText = String(format: "%.4f MHz", frequency)
        let title = name.isEmpty ? "Channel \(id)" : name
        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: title),
            subtitle: LocalizedStringResource(stringLiteral: freqText)
        )
    }

    var channelID: Int { Int(id) ?? 0 }
}

struct ChannelQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ChannelEntity] {
        let channels = await MainActor.run {
            RadioIntentBridge.shared.manager?.channels ?? []
        }
        let byID = Dictionary(uniqueKeysWithValues: channels.map { (String($0.channelID), $0) })
        return identifiers.compactMap { id in
            guard let ch = byID[id] else { return nil }
            return ChannelEntity(id: id, name: ch.name, frequency: ch.rxFreq)
        }
    }

    func suggestedEntities() async throws -> [ChannelEntity] {
        let channels = await MainActor.run {
            RadioIntentBridge.shared.manager?.channels ?? []
        }
        // Exclude special VFO (251, 252) and NOAA (253) channel IDs.
        return channels.filter { $0.channelID < 250 }.map {
            ChannelEntity(id: String($0.channelID), name: $0.name, frequency: $0.rxFreq)
        }
    }

    /// Resolves a spoken or typed channel name (e.g. "Repeater 1") to matching channels.
    func entities(matching string: String) async throws -> [ChannelEntity] {
        let channels = await MainActor.run {
            RadioIntentBridge.shared.manager?.channels ?? []
        }
        let query = string.lowercased()
        return channels
            .filter { $0.channelID < 250 && $0.name.lowercased().contains(query) }
            .map { ChannelEntity(id: String($0.channelID), name: $0.name, frequency: $0.rxFreq) }
    }
}

// MARK: - VFO Slot Enum

enum VFOSlot: String, AppEnum {
    case a = "A"
    case b = "B"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "VFO Slot")
    static var caseDisplayRepresentations: [VFOSlot: DisplayRepresentation] = [
        .a: "Channel A",
        .b: "Channel B",
    ]
}
