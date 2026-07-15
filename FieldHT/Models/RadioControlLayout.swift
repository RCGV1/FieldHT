import Combine
import Foundation

enum RadioControlSection: String, CaseIterable, Codable, Identifiable {
    case memoryGroup
    case monitorMode
    case primaryChannels
    case quickActions
    case channelNavigation
    case squelch
    case signalMeter
    case satellite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .memoryGroup: return "Memory Group"
        case .monitorMode: return "Monitor Mode"
        case .primaryChannels: return "Primary Channels"
        case .quickActions: return "Quick Actions"
        case .channelNavigation: return "Channel Navigation"
        case .squelch: return "Squelch Level"
        case .signalMeter: return "Signal Meter"
        case .satellite: return "Amateur Satellite"
        }
    }

    var systemImage: String {
        switch self {
        case .memoryGroup: return "square.stack.3d.up"
        case .monitorMode: return "dot.radiowaves.left.and.right"
        case .primaryChannels: return "rectangle.split.2x1"
        case .quickActions: return "bolt.fill"
        case .channelNavigation: return "arrow.left.arrow.right"
        case .squelch: return "speaker.wave.2"
        case .signalMeter: return "chart.bar.xaxis"
        case .satellite: return "globe.americas.fill"
        }
    }

    var isRemovable: Bool {
        switch self {
        case .primaryChannels: return false
        default: return true
        }
    }
}

struct RadioControlLayout: Codable, Equatable {
    static let defaultSections: [RadioControlSection] = [
        .memoryGroup,
        .monitorMode,
        .primaryChannels,
        .quickActions,
        .channelNavigation,
        .squelch,
        .signalMeter,
        .satellite
    ]

    var sections: [RadioControlSection]

    init(sections: [RadioControlSection] = Self.defaultSections) {
        self.sections = Self.normalized(sections)
    }

    mutating func move(fromOffsets: IndexSet, toOffset: Int) {
        let movedSections = fromOffsets.compactMap { index in
            sections.indices.contains(index) ? sections[index] : nil
        }
        let removedBeforeDestination = fromOffsets.filter { $0 < toOffset }.count

        for index in fromOffsets.sorted(by: >) where sections.indices.contains(index) {
            sections.remove(at: index)
        }

        let insertionIndex = max(0, min(toOffset - removedBeforeDestination, sections.count))
        sections.insert(contentsOf: movedSections, at: insertionIndex)
    }

    mutating func hide(_ section: RadioControlSection) {
        guard section.isRemovable else { return }
        sections.removeAll { $0 == section }
    }

    mutating func show(_ section: RadioControlSection) {
        guard section.isRemovable, !sections.contains(section) else { return }
        sections.append(section)
    }

    private static func normalized(_ candidate: [RadioControlSection]) -> [RadioControlSection] {
        var seen = Set<RadioControlSection>()
        var normalized = candidate.filter { seen.insert($0).inserted }

        if !normalized.contains(.primaryChannels) {
            normalized.insert(.primaryChannels, at: min(2, normalized.count))
        }

        return normalized
    }
}

@MainActor
final class RadioControlLayoutStore: ObservableObject {
    static let shared = RadioControlLayoutStore()

    private static let defaultsKey = "radioControlLayout"

    @Published private(set) var sections: [RadioControlSection]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let savedLayout = try? JSONDecoder().decode(RadioControlLayout.self, from: data) {
            sections = savedLayout.sections
        } else {
            sections = RadioControlLayout.defaultSections
        }
    }

    var hiddenSections: [RadioControlSection] {
        RadioControlSection.allCases.filter { $0.isRemovable && !sections.contains($0) }
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        var layout = RadioControlLayout(sections: sections)
        layout.move(fromOffsets: fromOffsets, toOffset: toOffset)
        save(layout)
    }

    func hide(_ section: RadioControlSection) {
        var layout = RadioControlLayout(sections: sections)
        layout.hide(section)
        save(layout)
    }

    func show(_ section: RadioControlSection) {
        var layout = RadioControlLayout(sections: sections)
        layout.show(section)
        save(layout)
    }

    func restoreDefaults() {
        save(RadioControlLayout())
    }

    private func save(_ layout: RadioControlLayout) {
        sections = layout.sections
        guard let data = try? JSONEncoder().encode(layout) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
