//
//  PFSettingsView.swift
//  FieldHT
//

import SwiftUI
import TipKit


struct ButtonTip: Tip {
    var title: Text {
        Text("Edit button actions")
    }
    var message: Text? {
        Text("Press the button image to switch which button you are editing")
    }
    var image: Image? {
        Image(systemName: "button.vertical.left.press.fill")
    }
}

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
                                        if selectedButtonIndex == 0 {
                                            selectedButtonIndex = 1
                                        } else {
                                            selectedButtonIndex = 0
                                        }
                                    }) {
                                        Image(selectedButtonIndex == 0 ? "ButtonsSelectOne" : "ButtonSelectTwo")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(height: 80)
                                    }
                                    .buttonStyle(.plain)

                                }
                                
                                Text("Selected Button \(selectedButtonIndex + 1)")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                TipView(ButtonTip())
                                    .padding()

                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    
                

                    // Trigger -> Action mapping
                    Section {
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
                    } header: {
                        Text("Trigger Actions")
                    } footer: {
                        Text("When the radio reports Press Down and Release slots, pair them for momentary actions such as PTT.")
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
        let triggers: [PFActionType] = [.shortSingle, .double, .long, .lowToHigh, .highToLow]

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
                    // Do NOT fall back to press/release slots when editing short press.
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
        viewModel.supportedPFActions
    }
    
    private func triggerDisplayName(_ action: PFActionType) -> String {
        switch action {
        case .invalid: return "Invalid"
        case .short: return "Short Press"
        case .long: return "Long Press"
        case .veryLong: return "Very Long Press"
        case .double: return "Double Press"
        case .`repeat`: return "Repeat"
        case .lowToHigh: return "Press Down (Physical Press)"
        case .highToLow: return "Release (Physical Release)"
        case .shortSingle: return "Short Press"
        case .longRelease: return "Long Release"
        case .veryLongRelease: return "Very Long Release"
        case .veryVeryLong: return "Very Very Long"
        case .veryVeryLongRelease: return "Very Very Long Release"
        case .triple: return "Triple Press"
        }
    }
    
    private func effectDisplayName(_ effect: PFEffectType) -> String {
        effect.displayName
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
