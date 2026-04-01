//
//  RadioAppIntents.swift
//  FieldHT
//
//  Siri / Shortcuts App Intents for radio control.
//  Every intent throws RadioNotConnectedError when no radio is connected via BLE.
//

import AppIntents
import Foundation

// MARK: - Switch Zone

struct SwitchZoneIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch Zone"
    static var description = IntentDescription(
        "Switch the radio to a different memory zone (group of channels)."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Zone")
    var zone: ZoneEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = try RadioIntentBridge.shared.requireConnected()
        manager.setRegion(zone.zoneIndex)
        return .result(dialog: "Switched to \(zone.name).")
    }
}

// MARK: - Switch Channel

struct SwitchChannelIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch Channel"
    static var description = IntentDescription(
        "Set channel A or B to a specific memory channel."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Channel")
    var channel: ChannelEntity

    @Parameter(title: "Slot", default: .a)
    var slot: VFOSlot

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = try RadioIntentBridge.shared.requireConnected()
        switch slot {
        case .a: manager.setChannelA(channel.channelID)
        case .b: manager.setChannelB(channel.channelID)
        }
        let slotLabel = slot == .a ? "A" : "B"
        let chName = channel.name.isEmpty ? "channel \(channel.id)" : channel.name
        return .result(dialog: "Channel \(slotLabel) set to \(chName).")
    }
}

// MARK: - Enter VFO Mode

struct EnterVFOModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Enter VFO Mode"
    static var description = IntentDescription(
        "Put channel A or B into free-tune VFO mode. VFO A uses channel ID 252, VFO B uses 251."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Slot", default: .a)
    var slot: VFOSlot

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = try RadioIntentBridge.shared.requireConnected()
        switch slot {
        case .a: manager.setChannelA(252) // VFO A channel ID
        case .b: manager.setChannelB(251) // VFO B channel ID
        }
        let label = slot == .a ? "A" : "B"
        return .result(dialog: "Channel \(label) is now in VFO mode.")
    }
}

// MARK: - Set Squelch

struct SetSquelchIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Squelch"
    static var description = IntentDescription(
        "Set the radio squelch level from 0 (open) to 9 (tightest)."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Level", default: 2)
    var level: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = try RadioIntentBridge.shared.requireConnected()
        let clamped = min(9, max(0, level))
        manager.setSquelch(clamped)
        return .result(dialog: "Squelch set to \(clamped).")
    }
}

// MARK: - Toggle Scan

struct ToggleScanIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Scan"
    static var description = IntentDescription(
        "Enable or disable channel scanning on the radio."
    )
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = try RadioIntentBridge.shared.requireConnected()
        let wasOn = manager.isScanning
        manager.toggleScan()
        return .result(dialog: wasOn ? "Scan disabled." : "Scan enabled.")
    }
}

// MARK: - Set Dual Watch

struct SetDualWatchIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Dual Watch"
    static var description = IntentDescription(
        "Enable or disable dual-watch so the radio monitors both channel A and B simultaneously."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Enabled")
    var enabled: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = try RadioIntentBridge.shared.requireConnected()
        manager.setDualWatch(enabled)
        return .result(dialog: enabled ? "Dual watch enabled." : "Dual watch disabled.")
    }
}

// MARK: - Set Power Saving Mode

struct SetPowerSavingIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Power Saving Mode"
    static var description = IntentDescription(
        "Enable or disable the radio's power saving mode to extend battery life."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Enabled")
    var enabled: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = try RadioIntentBridge.shared.requireConnected()
        guard let controller = manager.radioController,
              var settings = controller.state?.settings else {
            throw RadioNotConnectedError()
        }
        settings.powerSavingMode = enabled
        Task { try? await controller.setSettings(settings) }
        return .result(dialog: enabled ? "Power saving mode enabled." : "Power saving mode disabled.")
    }
}

// MARK: - Set Volume

struct SetVolumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Volume"
    static var description = IntentDescription(
        "Set the radio speaker volume from 0 (mute) to 100 (maximum)."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Volume", default: 50)
    var volume: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = try RadioIntentBridge.shared.requireConnected()
        let clamped = min(100, max(0, volume))
        manager.setVolume(clamped)
        return .result(dialog: "Volume set to \(clamped).")
    }
}

// MARK: - App Shortcuts (Siri phrases)

struct FieldHTShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SwitchZoneIntent(),
            phrases: [
                "Switch \(.applicationName) zone",
                "Change \(.applicationName) zone to \(\.$zone)",
                "Switch \(.applicationName) to zone \(\.$zone)",
            ],
            shortTitle: "Switch Zone",
            systemImageName: "map"
        )
        AppShortcut(
            intent: SwitchChannelIntent(),
            phrases: [
                "Switch \(.applicationName) channel",
                "Tune \(.applicationName) to \(\.$channel)",
                "Set \(.applicationName) to \(\.$channel)",
            ],
            shortTitle: "Switch Channel",
            systemImageName: "antenna.radiowaves.left.and.right"
        )
        AppShortcut(
            intent: EnterVFOModeIntent(),
            phrases: [
                "Enter \(.applicationName) VFO mode",
                "Switch \(.applicationName) to VFO mode",
            ],
            shortTitle: "VFO Mode",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: SetSquelchIntent(),
            phrases: [
                "Set \(.applicationName) squelch",
            ],
            shortTitle: "Set Squelch",
            systemImageName: "speaker.wave.2"
        )
        AppShortcut(
            intent: ToggleScanIntent(),
            phrases: [
                "Toggle \(.applicationName) scan",
                "Start \(.applicationName) scan",
                "Stop \(.applicationName) scan",
            ],
            shortTitle: "Toggle Scan",
            systemImageName: "arrow.triangle.2.circlepath"
        )
        AppShortcut(
            intent: SetDualWatchIntent(),
            phrases: [
                "Toggle \(.applicationName) dual watch",
                "Enable \(.applicationName) dual watch",
            ],
            shortTitle: "Dual Watch",
            systemImageName: "dot.radiowaves.left.and.right"
        )
        AppShortcut(
            intent: SetPowerSavingIntent(),
            phrases: [
                "Toggle \(.applicationName) power saving",
                "Enable \(.applicationName) power saving",
            ],
            shortTitle: "Power Saving",
            systemImageName: "battery.50"
        )
        AppShortcut(
            intent: SetVolumeIntent(),
            phrases: [
                "Set \(.applicationName) volume",
            ],
            shortTitle: "Set Volume",
            systemImageName: "speaker.3"
        )
    }
}
