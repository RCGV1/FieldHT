//
//  SettingsViewModel.swift
//  FieldHT
//
//  Created by Benjamin Faershtein on 12/13/25.
//

import Foundation
import Combine

/// View model for managing radio settings
@MainActor
public class SettingsViewModel: ObservableObject {
    @Published public var settings: Settings?
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String?
    @Published public var isSaving: Bool = false

    // PF (Programmable Function) settings
    @Published public var pfConfig: PFConfig?
    @Published public var supportedPFActions: [PFEffectType] = PFEffectType.knownCases
    @Published public var isPFLoading: Bool = false
    @Published public var pfErrorMessage: String?
    @Published public var isPFSaving: Bool = false
    @Published public var pfNoticeMessage: String?
    @Published public var pfLockedSlots: Set<String> = []
    @Published public var pfLastRedirect: PFRedirect?
    
    private var radioController: RadioController?
    private var settingsTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var pendingSettings: Settings?
    private var pfLoadTask: Task<Void, Never>?
    private var pfSaveTask: Task<Void, Never>?
    private var eventHandler: (() -> Void)?

    private struct LastPFEdit {
        let buttonID: Int
        let action: PFActionType
        let effect: PFEffectType
    }
    private var lastPFEdit: LastPFEdit?

    public struct PFRedirect: Equatable {
        public let buttonID: Int
        public let from: PFActionType
        public let toButtonID: Int
        public let to: PFActionType
        public let effect: PFEffectType
    }
    
    public init() {}

#if DEBUG
    private func logPFConfig(_ config: PFConfig, prefix: String) {
        print("[PF] \(prefix) entries=\(config.pf.count)")
        for (i, pf) in config.pf.enumerated() {
            print("[PF] \(prefix) [\(i)] button=\(pf.buttonID) trigger=\(pf.action) (\(pf.action.rawValue)) effect=\(pf.effect) (\(pf.effect.rawValue))")
        }
    }
#endif
    
    /// Set the radio controller and load settings
    public func setRadioController(_ controller: RadioController?) {
        print("SettingsViewModel: setRadioController called with \(controller == nil ? "nil" : "controller")")
        // Cancel previous tasks
        settingsTask?.cancel()
        saveTask?.cancel()
        saveTask = nil
        pendingSettings = nil
        pfLoadTask?.cancel()
        pfSaveTask?.cancel()
        eventHandler?()
        
        radioController = controller
        
        if let controller = controller {
            loadSettings()
            observeSettingsChanges(controller)
        } else {
            settings = nil
            pfConfig = nil
            supportedPFActions = PFEffectType.knownCases
            print("SettingsViewModel: Controller is nil, settings cleared")
        }
    }
    
    public func retryLoad() {
        print("SettingsViewModel: Retrying load...")
        loadSettings()
    }
    
    /// Load settings from the radio
    private func loadSettings() {
        guard let radioController = radioController else {
            print("SettingsViewModel: loadSettings failed - no radio controller")
            return
        }
        
        isLoading = true
        errorMessage = nil
        print("SettingsViewModel: Starting load settings...")
        
        settingsTask = Task {
            // Wait a bit to ensure radio is fully hydrated after connection
            // The radio needs time to complete the hydrate() process
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Check if radio is connected and has state
            guard radioController.isConnected else {
                await MainActor.run {
                    self.errorMessage = "Radio not fully connected"
                    self.isLoading = false
                    print("SettingsViewModel: Radio not connected (isConnected=false), cannot load settings")
                }
                return
            }
            
            // Access settings - isConnected already ensures state != nil
            // so this should be safe, but we'll add a check anyway
            await MainActor.run {
                // Double-check connection status on main actor
                guard radioController.isConnected else {
                    self.errorMessage = "Radio disconnected during load"
                    self.isLoading = false
                    print("SettingsViewModel: Radio disconnected during load check")
                    return
                }
                
                // Access settings - this is safe if isConnected is true
                let currentSettings = radioController.settings
                self.settings = currentSettings
                self.isLoading = false
                self.errorMessage = nil
                print("SettingsViewModel: Successfully loaded settings - Channel A: \(currentSettings.channelA), Channel B: \(currentSettings.channelB)")
            }
        }
    }
    
    /// Observe settings changes from the radio
    private func observeSettingsChanges(_ controller: RadioController) {
        eventHandler = controller.addEventHandler { [weak self] event in
            Task { @MainActor in
                guard let self = self else { return }
                if case .settingsChanged(let newSettings) = event {
                    self.settings = newSettings
                }
            }
        }
    }
    var isDualWatchOn: Bool {
        return settings?.doubleChannel != ChannelType.off.toProtocolValue()
    }

    func setDualWatch(_ isOn: Bool) {
        let newValue: ChannelType = isOn ? .a : .off
        updateDoubleChannel(newValue.toProtocolValue())
    }
    
    /// Update settings with a new Settings object
    public func updateSettings(_ newSettings: Settings) {
        guard let radioController = radioController else {
            return // Not connected
        }

        guard settings != newSettings else {
            print("SettingsViewModel: Skipping no-op settings save")
            return
        }
        
        // Optimistic update
        self.settings = newSettings
        
        pendingSettings = newSettings
        guard saveTask == nil else { return }

        saveTask = Task { [weak self, weak radioController] in
            guard let self, let radioController else { return }
            await self.flushPendingSettings(using: radioController)
        }
    }

    private func flushPendingSettings(using radioController: RadioController) async {
        while let nextSettings = pendingSettings {
            pendingSettings = nil
            isSaving = true
            errorMessage = nil
            print("SettingsViewModel: Attempting to save settings: \(nextSettings)")

            do {
                try await radioController.setSettings(nextSettings)
                print("SettingsViewModel: Settings saved successfully")
            } catch {
                errorMessage = error.localizedDescription
                print("SettingsViewModel: Failed to save settings. Error: \(error)")
                if let protocolError = error as? ProtocolError,
                   case .commandFailed(let status, let message) = protocolError {
                    print("SettingsViewModel: Command Failed Status: \(status), Message: \(message)")
                }

                if pendingSettings == nil,
                   let refreshedSettings = try? await radioController.refreshSettings() {
                    settings = refreshedSettings
                }
            }
        }

        isSaving = false
        saveTask = nil
    }
    
    /// Update channelA
    public func updateChannelA(_ value: Int) {
        guard var current = settings else { return }
        current.channelA = value
        updateSettings(current)
    }
    
    /// Update channelB
    public func updateChannelB(_ value: Int) {
        guard var current = settings else { return }
        current.channelB = value
        updateSettings(current)
    }
    
    /// Update scan
    public func updateScan(_ value: Bool) {
        guard var current = settings else { return }
        current.scan = value
        updateSettings(current)
    }
    
    /// Update squelchLevel
    public func updateSquelchLevel(_ value: Int) {
        guard var current = settings else { return }
        current.squelchLevel = value
        updateSettings(current)
    }
    
    /// Update micGain
    public func updateMicGain(_ value: Int) {
        guard var current = settings else { return }
        current.micGain = value
        updateSettings(current)
    }
    
    /// Update btMicGain
    public func updateBtMicGain(_ value: Int) {
        guard var current = settings else { return }
        current.btMicGain = value
        updateSettings(current)
    }
    
    /// Update localSpeaker
    public func updateLocalSpeaker(_ value: Int) {
        guard var current = settings else { return }
        current.localSpeaker = value
        updateSettings(current)
    }
    
    /// Update hmSpeaker
    public func updateHmSpeaker(_ value: Int) {
        guard var current = settings else { return }
        current.hmSpeaker = value
        updateSettings(current)
    }
    
    /// Update txHoldTime
    public func updateTxHoldTime(_ value: Int) {
        guard var current = settings else { return }
        current.txHoldTime = value
        updateSettings(current)
    }
    
    /// Update txTimeLimit
    public func updateTxTimeLimit(_ value: Int) {
        guard var current = settings else { return }
        current.txTimeLimit = value
        updateSettings(current)
    }
    
    /// Update autoPowerOff
    public func updateAutoPowerOff(_ value: Int) {
        guard var current = settings else { return }
        current.autoPowerOff = value
        updateSettings(current)
    }
    
    /// Update screenTimeout
    public func updateScreenTimeout(_ value: Int) {
        guard var current = settings else { return }
        current.screenTimeout = value
        updateSettings(current)
    }
    
    /// Update tailElim
    public func updateTailElim(_ value: Bool) {
        guard var current = settings else { return }
        current.tailElim = value
        updateSettings(current)
    }
    
    /// Update autoRelayEn
    public func updateAutoRelayEn(_ value: Bool) {
        guard var current = settings else { return }
        current.autoRelayEn = value
        updateSettings(current)
    }
    
    /// Update autoPowerOn
    public func updateAutoPowerOn(_ value: Bool) {
        guard var current = settings else { return }
        current.autoPowerOn = value
        updateSettings(current)
    }
    
    /// Update keepAghfpLink
    public func updateKeepAghfpLink(_ value: Bool) {
        guard var current = settings else { return }
        current.keepAghfpLink = value
        updateSettings(current)
    }
    
    /// Update adaptiveResponse
    public func updateAdaptiveResponse(_ value: Bool) {
        guard var current = settings else { return }
        current.adaptiveResponse = value
        updateSettings(current)
    }
    
    /// Update disTone
    public func updateDisTone(_ value: Bool) {
        guard var current = settings else { return }
        current.disTone = value
        updateSettings(current)
    }
    
    /// Update powerSavingMode
    public func updatePowerSavingMode(_ value: Bool) {
        guard var current = settings else { return }
        current.powerSavingMode = value
        updateSettings(current)
    }
    
    /// Update useFreqRange2
    public func updateUseFreqRange2(_ value: Bool) {
        guard var current = settings else { return }
        current.useFreqRange2 = value
        updateSettings(current)
    }
    
    /// Update pttLock
    public func updatePttLock(_ value: Bool) {
        guard var current = settings else { return }
        current.pttLock = value
        updateSettings(current)
    }
    
    /// Update leadingSyncBitEn
    public func updateLeadingSyncBitEn(_ value: Bool) {
        guard var current = settings else { return }
        current.leadingSyncBitEn = value
        updateSettings(current)
    }
    
    /// Update pairingAtPowerOn
    public func updatePairingAtPowerOn(_ value: Bool) {
        guard var current = settings else { return }
        current.pairingAtPowerOn = value
        updateSettings(current)
    }
    
    /// Update imperialUnit
    public func updateImperialUnit(_ value: Bool) {
        guard var current = settings else { return }
        current.imperialUnit = value
        updateSettings(current)
    }
    
    /// Update disDigitalMute
    public func updateDisDigitalMute(_ value: Bool) {
        guard var current = settings else { return }
        current.disDigitalMute = value
        updateSettings(current)
    }
    
    /// Update signalingEccEn
    public func updateSignalingEccEn(_ value: Bool) {
        guard var current = settings else { return }
        current.signalingEccEn = value
        updateSettings(current)
    }
    
    /// Update chDataLock
    public func updateChDataLock(_ value: Bool) {
        guard var current = settings else { return }
        current.chDataLock = value
        updateSettings(current)
    }
    
    /// Update Double Channel
    public func updateDoubleChannel(_ value: Int) {
        guard var current = settings else { return }
        current.doubleChannel = value
        updateSettings(current)
    }

    /// Update wxMode
    public func updateWxMode(_ value: Int) {
        guard var current = settings else { return }
        current.wxMode = value
        updateSettings(current)
    }

    /// Update noaaCh
    public func updateNoaaCh(_ value: Int) {
        guard var current = settings else { return }
        current.noaaCh = value
        updateSettings(current)
    }

    /// Update aghfpCallMode
    public func updateAghfpCallMode(_ value: Int) {
        guard var current = settings else { return }
        current.aghfpCallMode = value
        updateSettings(current)
    }

    /// Update positioningSystem
    public func updatePositioningSystem(_ value: Int) {
        guard var current = settings else { return }
        current.positioningSystem = value
        updateSettings(current)
    }

    /// Load PF configuration from the radio
    public func loadPFConfig() {
        guard let radioController = radioController else {
            pfErrorMessage = "Not connected to radio"
            return
        }
        
        isPFLoading = true
        pfErrorMessage = nil
        pfNoticeMessage = nil
        pfLockedSlots = []
        pfLastRedirect = nil
        
        pfLoadTask = Task {
            do {
                async let configTask = radioController.getPF()
                async let actionsTask = loadSupportedPFActions(from: radioController)
                let config = try await configTask
                let supportedActions = try await actionsTask
                 
                await MainActor.run {
                    self.pfConfig = config
                    self.supportedPFActions = supportedActions
                    self.isPFLoading = false
                    self.pfErrorMessage = nil
                    self.pfNoticeMessage = nil
                    let buttonCount = Set(config.pf.map { $0.buttonID }).count
                    print("SettingsViewModel: Successfully loaded PF config (entries=\(config.pf.count), buttons=\(buttonCount))")
#if DEBUG
                    self.logPFConfig(config, prefix: "RX")
#endif
                }
            } catch {
                await MainActor.run {
                    self.isPFLoading = false
                    self.pfErrorMessage = "Failed to load PF config: \(error.localizedDescription)"
                    print("SettingsViewModel: Failed to load PF config: \(error)")
                }
            }
        }
    }

    private func loadSupportedPFActions(from radioController: RadioController) async throws -> [PFEffectType] {
        let payload = try await radioController.getPFActionsRaw()
        let reported = payload.map { PFEffectType(rawValue: Int($0)) }
        let merged = Array(Set(reported + PFEffectType.knownCases)).sorted { $0.rawValue < $1.rawValue }
        print("[PF] Supported actions from radio: \(merged.map { "\($0.displayName) [\($0.rawValue)]" }.joined(separator: ", "))")
        return merged
    }
    
    /// Update a specific PF button configuration
    public func updatePFButton(buttonID: Int, action: PFActionType, effect: PFEffectType) {
        guard let config = pfConfig else {
            pfErrorMessage = "PF config not loaded"
            return
        }

        var updatedPF = config.pf

        // Firmware variance:
        // "Short press" may be stored under different PFActionType slots depending on firmware.
        // IMPORTANT: Some radios expose both `.shortSingle` and edge-trigger slots (eg `.lowToHigh`).
        // Treat them as distinct. Only update ONE existing short-press slot per button:
        // prefer `.shortSingle` when present, else fall back to other known variants.
        // Never grow/repack the PF table (order and size are often device-defined).
        var editedAction = action

        if action == .shortSingle {
            // Do NOT fall back to edge-trigger slots (eg `.lowToHigh`).
            // Some firmwares expose both a short-press slot and edge-trigger slots; treating them
            // as interchangeable causes accidental clobbering.
            let candidates: [PFActionType] = [.shortSingle, .short, .invalid]

            guard let chosen = candidates.first(where: { candidate in
                updatedPF.contains(where: { $0.buttonID == buttonID && $0.action == candidate })
            }) else {
                pfErrorMessage = "This radio didn't expose a Short Press slot for button \(buttonID)"
                return
            }

            editedAction = chosen

            let indices = updatedPF.indices.filter { updatedPF[$0].buttonID == buttonID && updatedPF[$0].action == chosen }
            for idx in indices {
                updatedPF[idx] = PF(buttonID: buttonID, action: chosen, effect: effect)
            }
        } else {
            // IMPORTANT: Many radios treat the PF table as fixed-size and/or order-dependent.
            // Never grow the array (appending can cause the device to ignore new entries).
            if let index = updatedPF.firstIndex(where: { $0.buttonID == buttonID && $0.action == action }) {
                updatedPF[index] = PF(buttonID: buttonID, action: action, effect: effect)
            } else {
                // Avoid guessing/repacking slots for triggers the radio didn't expose.
                pfErrorMessage = "This radio didn't expose a slot for \(triggerName(action)) on button \(buttonID)"
                return
            }
        }
        
        // Create new config
        let newConfig = PFConfig(pf: updatedPF)

        // Track the last edit so we can mark firmware-locked slots.
        lastPFEdit = LastPFEdit(buttonID: buttonID, action: editedAction, effect: effect)
        
        // Optimistic update
        self.pfConfig = newConfig
        
        // Save immediately
        savePFConfig(newConfig)
    }
    
    /// Save PF configuration to the radio
    private func savePFConfig(_ config: PFConfig) {
        guard let radioController = radioController else {
            pfErrorMessage = "Not connected to radio"
            return
        }
        
        // Cancel previous save task
        pfSaveTask?.cancel()
        
        isPFSaving = true
        pfErrorMessage = nil
        pfNoticeMessage = nil
        pfLastRedirect = nil
        
        pfSaveTask = Task {
            do {
#if DEBUG
                await MainActor.run {
                    self.logPFConfig(config, prefix: "TX")
                }
#endif
                try await radioController.setPF(config)

                // Read-back verification (keeps UI in sync with device-defined slots)
                // Some firmwares apply PF writes asynchronously and/or normalize entries.
                // Poll until results stabilize to avoid transient diffs.
                try? await Task.sleep(nanoseconds: 250_000_000)
                let verified = try await self.readPFStable(radioController, timeoutNanoseconds: 2_000_000_000)

                await MainActor.run {
                    self.pfConfig = verified
                    self.isPFSaving = false
                    print("SettingsViewModel: Successfully saved PF config")
                    let diffs = self.pfDiffs(expected: config, verified: verified)
                    if !diffs.isEmpty {
                        self.pfNoticeMessage = self.formatPFDiffNotice(diffs, expected: config, verified: verified)
                    }

                    // If the last edited slot didn't stick, try to detect a firmware "redirect".
                    // Only mark the slot as locked when we have no evidence that the requested
                    // effect landed anywhere new.
                    if let edit = self.lastPFEdit {
                        let verifiedEditedEffects = verified.pf
                            .filter { $0.buttonID == edit.buttonID && $0.action == edit.action }
                            .map { $0.effect }

                        if verifiedEditedEffects.contains(edit.effect) {
                            // The edit stuck as-written.
                        } else if let redirected = self.redirectedAction(
                            buttonID: edit.buttonID,
                            desired: edit.effect,
                            editedAction: edit.action,
                            expected: config,
                            verified: verified
                        ) {
                            self.pfLastRedirect = PFRedirect(
                                buttonID: edit.buttonID,
                                from: edit.action,
                                toButtonID: edit.buttonID,
                                to: redirected,
                                effect: edit.effect
                            )
                        } else if let landed = self.findLandingSlotAnyButton(desired: edit.effect, expected: config, verified: verified) {
                            self.pfLastRedirect = PFRedirect(
                                buttonID: edit.buttonID,
                                from: edit.action,
                                toButtonID: landed.buttonID,
                                to: landed.action,
                                effect: edit.effect
                            )
                        } else {
                            self.pfLockedSlots.insert(self.pfSlotKey(buttonID: edit.buttonID, action: edit.action))
                        }
                    }
#if DEBUG
                    self.logPFDiff(diffs)
#endif
                }
            } catch {
                await MainActor.run {
                    self.isPFSaving = false
                    self.pfErrorMessage = "Failed to save PF config: \(error.localizedDescription)"
                    print("SettingsViewModel: Failed to save PF config: \(error)")
                    
                    // Reload on failure to revert optimistic update
                    self.loadPFConfig()
                }
            }
        }
    }

#if DEBUG
    private func logPFDiff(_ diffs: [PFDiff]) {
        if diffs.isEmpty {
            print("[PF] Verify OK (no diffs)")
            return
        }

        print("[PF] Verify diffs=\(diffs.count)")
        for diff in diffs {
            let expStr = diff.expected.isEmpty ? "<missing>" : diff.expected.map { "\($0) (\($0.rawValue))" }.joined(separator: ", ")
            let verStr = diff.verified.isEmpty ? "<missing>" : diff.verified.map { "\($0) (\($0.rawValue))" }.joined(separator: ", ")
            print("[PF] DIFF b=\(diff.buttonID) a=\(diff.action.rawValue) expected=\(expStr) verified=\(verStr)")
        }
    }
#endif

    private struct PFDiff {
        let buttonID: Int
        let action: PFActionType
        let expected: [PFEffectType]
        let verified: [PFEffectType]
    }

    private func pfDiffs(expected: PFConfig, verified: PFConfig) -> [PFDiff] {
        struct Key: Hashable {
            let buttonID: Int
            let actionRaw: Int
        }

        func key(_ pf: PF) -> Key {
            Key(buttonID: pf.buttonID, actionRaw: pf.action.rawValue)
        }

        func group(_ pfs: [PF]) -> [Key: [PFEffectType]] {
            var out: [Key: [PFEffectType]] = [:]
            for pf in pfs {
                out[key(pf), default: []].append(pf.effect)
            }

            // Stabilize comparisons (device may reorder entries with same key).
            for k in out.keys {
                out[k]?.sort { $0.rawValue < $1.rawValue }
            }
            return out
        }

        let expectedByKey = group(expected.pf)
        let verifiedByKey = group(verified.pf)

        let allKeys = Set(expectedByKey.keys).union(verifiedByKey.keys)
        var diffs: [PFDiff] = []
        diffs.reserveCapacity(allKeys.count)

        for k in allKeys {
            let exp = expectedByKey[k] ?? []
            let ver = verifiedByKey[k] ?? []
            if exp != ver {
                let action = PFActionType(rawValue: k.actionRaw) ?? .invalid
                diffs.append(PFDiff(buttonID: k.buttonID, action: action, expected: exp, verified: ver))
            }
        }

        diffs.sort {
            if $0.buttonID != $1.buttonID { return $0.buttonID < $1.buttonID }
            return $0.action.rawValue < $1.action.rawValue
        }
        return diffs
    }

    private func formatPFDiffNotice(_ diffs: [PFDiff], expected: PFConfig, verified: PFConfig) -> String {
        let count = diffs.count
        let shown = diffs.prefix(3).map { diff in
            let actionName = triggerName(diff.action)
            let expectedEffect = diff.expected.first
            let verifiedEffect = diff.verified.first

            let expectedName = expectedEffect.map(effectName) ?? "<missing>"
            let verifiedName = verifiedEffect.map(effectName) ?? "<missing>"

            var extra: String = ""
            if let desired = expectedEffect {
                if let redirected = redirectedAction(buttonID: diff.buttonID, desired: desired, editedAction: diff.action, expected: expected, verified: verified) {
                    extra = " (saved as \(triggerName(redirected)))"
                } else if verifiedEffect != desired {
                    extra = " (rejected by firmware)"
                }
            }

            return "Button ID \(diff.buttonID) \(actionName): \(expectedName) -> \(verifiedName)\(extra)"
        }
        let suffix = count > 3 ? " (+\(count - 3) more)" : ""
        return "Radio adjusted PF mappings after save. " + shown.joined(separator: " | ") + suffix
    }

    private func redirectedAction(buttonID: Int, desired: PFEffectType, editedAction: PFActionType, expected: PFConfig, verified: PFConfig) -> PFActionType? {
        // If the radio ignores a slot but applies the requested effect to a different slot
        // for the same button, surface where it actually landed.
        // To reduce false-positives, require that the landing slot changed compared to `expected`.
        let expectedByAction: [Int: PFEffectType] = Dictionary(
            expected.pf
                .filter { $0.buttonID == buttonID }
                .map { ($0.action.rawValue, $0.effect) },
            uniquingKeysWith: { a, _ in a }
        )

        let verifiedForButton = verified.pf.filter { $0.buttonID == buttonID }
        let candidates = verifiedForButton
            .filter { $0.action != editedAction && $0.effect == desired }
            .sorted { $0.action.rawValue < $1.action.rawValue }

        for candidate in candidates {
            let prior = expectedByAction[candidate.action.rawValue]
            if prior != desired {
                return candidate.action
            }
        }
        return nil
    }

    private func pfSlotKey(buttonID: Int, action: PFActionType) -> String {
        "b=\(buttonID) a=\(action.rawValue)"
    }

    private nonisolated func pfSignature(_ config: PFConfig) -> String {
        struct Key: Hashable {
            let buttonID: Int
            let actionRaw: Int
        }

        var grouped: [Key: [Int]] = [:]
        for pf in config.pf {
            let k = Key(buttonID: pf.buttonID, actionRaw: pf.action.rawValue)
            grouped[k, default: []].append(pf.effect.rawValue)
        }

        return grouped
            .map { (k, effects) in
                let effectStr = effects.sorted().map(String.init).joined(separator: ",")
                return "\(k.buttonID):\(k.actionRaw)=\(effectStr)"
            }
            .sorted()
            .joined(separator: "|")
    }

    private nonisolated func readPFStable(
        _ radioController: RadioController,
        timeoutNanoseconds: UInt64,
        pollEveryNanoseconds: UInt64 = 250_000_000,
        requiredRepeats: Int = 1
    ) async throws -> PFConfig {
        let start = DispatchTime.now().uptimeNanoseconds

        var lastSig: String?
        var repeats = 0
        var lastConfig: PFConfig?

        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            let cfg = try await radioController.getPF()
            let sig = pfSignature(cfg)

            if sig == lastSig {
                repeats += 1
                if repeats >= requiredRepeats {
                    return cfg
                }
            } else {
                lastSig = sig
                repeats = 0
            }

            lastConfig = cfg
            try? await Task.sleep(nanoseconds: pollEveryNanoseconds)
        }

        if let lastConfig {
            return lastConfig
        }
        return try await radioController.getPF()
    }

    private struct LandingSlot {
        let buttonID: Int
        let action: PFActionType
    }

    private func findLandingSlotAnyButton(desired: PFEffectType, expected: PFConfig, verified: PFConfig) -> LandingSlot? {
        // Find a slot where the desired effect appears in the verified config but was NOT present
        // in the same slot of the expected config.
        // This helps identify firmware "redirects" that spill into other buttons/triggers.
        for pf in verified.pf {
            guard pf.effect == desired else { continue }
            if let expectedMatch = expected.pf.first(where: { $0.buttonID == pf.buttonID && $0.action == pf.action }) {
                if expectedMatch.effect == desired {
                    continue
                }
            }

            return LandingSlot(buttonID: pf.buttonID, action: pf.action)
        }
        return nil
    }

    private func effectName(_ effect: PFEffectType) -> String {
        effect.shortName
    }

    private func triggerName(_ action: PFActionType) -> String {
        switch action {
        case .invalid, .shortSingle:
            return "Short Press"
        case .double:
            return "Double Press"
        case .long:
            return "Long Press"
        case .lowToHigh:
            return "Press Down (Physical Press)"
        default:
            return "Trigger \(action.rawValue)"
        }
    }
}

enum SettingsError: LocalizedError {
    case notConnected
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to radio"
        }
    }
}
