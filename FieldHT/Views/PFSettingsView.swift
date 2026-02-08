//
//  PFSettingsView.swift
//  FieldHT
//

import SwiftUI

struct PFSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let radioController: RadioController
    
    @State private var selectedButtonIndex: Int = 0
    
    init(radioController: RadioController, viewModel: SettingsViewModel) {
        self.radioController = radioController
        self.viewModel = viewModel
    }
    
    var body: some View {
        Group {
            if viewModel.isPFLoading {
                ProgressView("Loading PF settings...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.pfErrorMessage {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    Text("Error")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("Retry") {
                        viewModel.loadPFConfig()
                    }
                    .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.pfConfig != nil {
                Form {
                    if let redirect = viewModel.pfLastRedirect, redirect.buttonID == selectedButtonID {
                        Section {
                            Text(redirectText(redirect))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let notice = viewModel.pfNoticeMessage {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(notice)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)

                                Button("Dismiss") {
                                    viewModel.pfNoticeMessage = nil
                                }
                                .font(.footnote)
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    // Button Selector Section
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 16) {
                                // Button Images
                                HStack(spacing: 20) {
                                    Button(action: {
                                        selectedButtonIndex = 0
                                    }) {
                                        Image(selectedButtonIndex == 0 ? "ButtonsSelectOne" : "Buttons")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(height: 80)
                                    }
                                    .buttonStyle(.plain)

                                    if buttonIDs.count > 1 {
                                        Button(action: {
                                            selectedButtonIndex = 1
                                        }) {
                                            Image(selectedButtonIndex == 1 ? "ButtonSelectTwo" : "Buttons")
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(height: 80)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                
                                Text("Selected Button \(selectedButtonIndex + 1)")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }

                    // Trigger -> Action mapping
                    Section(header: Text("Trigger Actions")) {
                        ForEach(availableTriggers, id: \.self) { trigger in
                            HStack {
                                Text(triggerDisplayName(trigger))
                                Spacer()
                                Picker("Action", selection: effectBinding(for: trigger)) {
                                    ForEach(allEffects, id: \.self) { effect in
                                        Text(effectDisplayName(effect)).tag(effect)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .disabled(viewModel.pfLockedSlots.contains(pfSlotKey(buttonID: selectedButtonID, action: lockAction(for: trigger))))
                            }
                        }
                    }
                }
                .disabled(viewModel.isPFSaving)
            } else {
                ContentUnavailableView {
                    Label("No PF Config", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("PF configuration not available")
                }
            }
        }
        .navigationTitle("Programmable Buttons")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.isPFSaving {
                    ProgressView()
                }
            }
        }
        .onAppear {
            viewModel.loadPFConfig()
        }
        .onChange(of: viewModel.pfConfig?.pf.count) { _, _ in
            // Clamp selection if the device reports fewer buttons than expected.
            if selectedButtonIndex >= buttonIDs.count {
                selectedButtonIndex = 0
            }
        }
    }
    
    // Get available triggers for the selected button
    private var availableTriggers: [PFActionType] {
        // Keep the UI intentionally small by default.
        let triggers: [PFActionType] = [.shortSingle, .double, .long]

        // Only show triggers the device actually exposed for this button.
        guard let pfConfig = viewModel.pfConfig else { return triggers }
        let available = Set(pfConfig.pf.filter { $0.buttonID == selectedButtonID }.map { $0.action })
        return triggers.filter { available.contains($0) }
    }

    private var buttonIDs: [Int] {
        guard let pfConfig = viewModel.pfConfig else { return [0, 1] }
        let ids = Set(pfConfig.pf.map { $0.buttonID })
        let sorted = ids.sorted()
        return sorted.isEmpty ? [0, 1] : sorted
    }

    private var selectedButtonID: Int {
        if buttonIDs.indices.contains(selectedButtonIndex) {
            return buttonIDs[selectedButtonIndex]
        }
        return buttonIDs.first ?? 0
    }

    private func effectBinding(for trigger: PFActionType) -> Binding<PFEffectType> {
        Binding(
            get: {
                guard let pfConfig = viewModel.pfConfig else { return .disable }
                let forButton = pfConfig.pf.filter { $0.buttonID == selectedButtonID }

                // For Short Press, firmware may store the mapping in different action slots.
                if trigger == .shortSingle {
                    // If the radio redirected the last edit, show the slot it actually wrote.
                    if let redirect = viewModel.pfLastRedirect,
                       redirect.buttonID == selectedButtonID,
                       redirect.from == .shortSingle,
                       redirect.toButtonID == selectedButtonID,
                       let redirectedEntry = forButton.first(where: { $0.action == redirect.to }) {
                        return redirectedEntry.effect
                    }

                    // Prefer the explicit short-press slot when it exists.
                    // Only fall back to variants on radios that don't expose `.shortSingle`.
                    // Do NOT fall back to edge-trigger slots (eg `.lowToHigh`).
                    let candidates: [PFActionType] = [.shortSingle, .short, .invalid]
                    for candidate in candidates {
                        if let entry = forButton.first(where: { $0.action == candidate }) {
                            return entry.effect
                        }
                    }
                }
                return forButton.first(where: { $0.action == trigger })?.effect ?? .disable
            },
            set: { newEffect in
                viewModel.updatePFButton(buttonID: selectedButtonID, action: trigger, effect: newEffect)
            }
        )
    }

    private func lockAction(for trigger: PFActionType) -> PFActionType {
        // Align the lock key with the actual slot used for short-press.
        guard trigger == .shortSingle else { return trigger }

        guard let pfConfig = viewModel.pfConfig else { return .shortSingle }
        let forButton = pfConfig.pf.filter { $0.buttonID == selectedButtonID }
        let candidates: [PFActionType] = [.shortSingle, .short, .invalid]
        for candidate in candidates {
            if forButton.contains(where: { $0.action == candidate }) {
                return candidate
            }
        }
        return .shortSingle
    }

    private func redirectText(_ redirect: SettingsViewModel.PFRedirect) -> String {
        if redirect.toButtonID != redirect.buttonID {
            return "Radio saved your last change on Button \(redirect.toButtonID + 1) \(triggerDisplayName(redirect.to))."
        }
        return "Radio saved your last change as \(triggerDisplayName(redirect.to))."
    }

    private func pfSlotKey(buttonID: Int, action: PFActionType) -> String {
        "b=\(buttonID) a=\(action.rawValue)"
    }
    
    // All available effects
    private var allEffects: [PFEffectType] {
        [
            .disable,
            .alarm,
            .alarmAndMute,
            .toggleOffline,
            .toggleRadioTx,
            .toggleTxPower,
            .toggleFM,
            .prevChannel,
            .nextChannel,
            .tCall,
            .prevRegion,
            .nextRegion,
            .toggleChScan,
            .mainPTT,
            .subPTT,
            .toggleMonitor,
            .btPairing,
            .toggleDoubleCh,
            .toggleABCh,
            .sendLocation,
            .oneClickLink,
            .volDown,
            .volUp,
            .toggleMute
        ]
    }
    
    private func triggerDisplayName(_ action: PFActionType) -> String {
        switch action {
        case .invalid: return "Invalid"
        case .short: return "Short Press"
        case .long: return "Long Press"
        case .veryLong: return "Very Long Press"
        case .double: return "Double Press"
        case .`repeat`: return "Repeat"
        case .lowToHigh: return "Press Down"
        case .highToLow: return "High to Low"
        case .shortSingle: return "Short Press"
        case .longRelease: return "Long Release"
        case .veryLongRelease: return "Very Long Release"
        case .veryVeryLong: return "Very Very Long"
        case .veryVeryLongRelease: return "Very Very Long Release"
        case .triple: return "Triple Press"
        }
    }
    
    private func effectDisplayName(_ effect: PFEffectType) -> String {
        switch effect {
        case .disable: return "Disable"
        case .alarm: return "Alarm"
        case .alarmAndMute: return "Alarm and Mute"
        case .toggleOffline: return "Toggle Standby"
        case .toggleRadioTx: return "Toggle Radio TX"
        case .toggleTxPower: return "Toggle TX Power"
        case .toggleFM: return "Toggle FM"
        case .prevChannel: return "Previous Channel"
        case .nextChannel: return "Next Channel"
        case .tCall: return "T-Call"
        case .prevRegion: return "Previous Region"
        case .nextRegion: return "Next Region"
        case .toggleChScan: return "Toggle Channel Scan"
        case .mainPTT: return "Main PTT"
        case .subPTT: return "Sub PTT"
        case .toggleMonitor: return "Toggle Monitor"
        case .btPairing: return "BT Pairing"
        case .toggleDoubleCh: return "Toggle Double Channel"
        case .toggleABCh: return "Toggle A/B Channel"
        case .sendLocation: return "Send Location"
        case .oneClickLink: return "One Click Link"
        case .volDown: return "Volume Down"
        case .volUp: return "Volume Up"
        case .toggleMute: return "Toggle Mute"
        }
    }
}

#Preview {
    NavigationView {
        PFSettingsView(
            radioController: RadioController.newBLE(deviceUUID: UUID(), radioManager: RadioManager()),
            viewModel: SettingsViewModel()
        )
    }
}
