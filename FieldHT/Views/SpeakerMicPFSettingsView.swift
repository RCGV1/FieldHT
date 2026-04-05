import SwiftUI

struct SpeakerMicPFSettingsView: View {
    @ObservedObject var controller: SpeakerMicController

    @State private var selectedButtonID: Int = 0

    private let supportedBS22ButtonIDs = [0, 1, 2, 3]

    private var isSupportedModel: Bool {
        controller.isBS22
    }

    private var buttonIDs: [Int] {
        let ids = Set(controller.pfConfig.pf.map(\.buttonID))
        let sorted = ids.sorted()
        let fallback = sorted.isEmpty ? supportedBS22ButtonIDs : sorted
        if controller.isBS22 {
            return supportedBS22ButtonIDs.filter { fallback.contains($0) || supportedBS22ButtonIDs.contains($0) }
        }
        return fallback
    }

    private var availableTriggers: [PFActionType] {
        let preferred: [PFActionType] = [.shortSingle, .double, .long, .lowToHigh]
        let seen = Set(controller.pfConfig.pf.filter { $0.buttonID == selectedButtonID }.map(\.action))
        return preferred.filter { seen.contains($0) }
    }

    private var allEffects: [PFEffectType] {
        let effects = controller.supportedActions
        return effects.isEmpty ? [.disable] : effects
    }

    var body: some View {
        Group {
            if isSupportedModel {
                supportedEditor
            } else {
                unsupportedView
            }
        }
        .navigationTitle("Speaker Mic Buttons")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if controller.isSavingPF {
                    ProgressView()
                }
            }
        }
        .onAppear {
            if !buttonIDs.contains(selectedButtonID) {
                selectedButtonID = buttonIDs.first ?? 0
            }
        }
        .onChange(of: controller.pfConfig.pf.count) {
            if !buttonIDs.contains(selectedButtonID) {
                selectedButtonID = buttonIDs.first ?? 0
            }
        }
    }

    private var supportedEditor: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("BS22 Mic Button Setup")
                        .font(.headline)
                    Text("Pick a physical button first, then assign the actions the mic actually exposes for it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Select a Button") {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        selectorCard(for: 0)
                        selectorCard(for: 1)
                    }

                    HStack(spacing: 12) {
                        selectorCard(for: 2)
                        selectorCard(for: 3)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(availableTriggers, id: \.self) { trigger in
                    Picker(triggerDisplayName(trigger), selection: effectBinding(for: trigger)) {
                        ForEach(allEffects, id: \.self) { effect in
                            Text(effect.displayName).tag(effect)
                        }
                    }
                    .disabled(controller.isSavingPF)
                }
            } header: {
                Text("\(buttonTitle(for: selectedButtonID)) Actions")
            } footer: {
                Text(buttonSummary(for: selectedButtonID))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error = controller.errorMessage, !error.isEmpty {
                Section("Accessory Issue") {
                    Text(error)
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            }
        }
    }

    private var unsupportedView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 24)

                Image(systemName: "mic.badge.xmark")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(.orange)

                Text("This Speaker Mic Isn’t Mapped Yet")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("FieldHT knows the BS22 button layout right now. This connected mic reports as \(controller.modelName), so I need the hardware in hand to map its button positions correctly.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("Support the next mic so I can buy it, decode it, and add proper button setup.")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                VStack(spacing: 14) {
                    Link(destination: URL(string: "https://buymeacoffee.com/benfaer")!) {
                        Text("Help Fund Support for This Mic")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    SupportDeveloperRow()
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )

                Spacer(minLength: 24)
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    @ViewBuilder
    private func selectorCard(for buttonID: Int) -> some View {
        Button {
            selectedButtonID = buttonID
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                if let assetName = assetName(for: buttonID) {
                    Image(assetName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    Image(systemName: symbolName(for: buttonID))
                        .font(.system(size: 30, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 96)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(selectedButtonID == buttonID ? Color.accentColor.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(buttonTitle(for: buttonID))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(buttonSubtitle(for: buttonID))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 158, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(selectedButtonID == buttonID ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func effectBinding(for trigger: PFActionType) -> Binding<PFEffectType> {
        Binding(
            get: {
                controller.pfConfig.pf.first(where: { $0.buttonID == selectedButtonID && $0.action == trigger })?.effect ?? .disable
            },
            set: { newValue in
                Task {
                    try? await controller.updatePF(buttonID: selectedButtonID, action: trigger, effect: newValue)
                }
            }
        )
    }

    private func buttonTitle(for buttonID: Int) -> String {
        switch buttonID {
        case 0: return "Button 1"
        case 1: return "Button 2"
        case 2: return "Button 3"
        case 3: return "Button 4"
        default: return "Button \(buttonID + 1)"
        }
    }

    private func buttonSubtitle(for buttonID: Int) -> String {
        switch buttonID {
        case 0: return "Closest to PTT"
        case 1: return "Farthest from PTT"
        case 2: return "Up button"
        case 3: return "Down button"
        default: return "Accessory button"
        }
    }

    private func buttonSummary(for buttonID: Int) -> String {
        let assignments = controller.pfConfig.pf
            .filter { $0.buttonID == buttonID }
            .sorted { $0.action.rawValue < $1.action.rawValue }
            .map { "\(triggerDisplayName($0.action)): \($0.effect.shortName)" }
        return assignments.isEmpty ? "No actions exposed for this button yet." : assignments.joined(separator: " • ")
    }

    private func assetName(for buttonID: Int) -> String? {
        switch buttonID {
        case 2:
            return selectedButtonID == buttonID ? "BS22UpButtonSelected" : "BS22TopButtonsNoneSelected"
        case 3:
            return selectedButtonID == buttonID ? "BS22DownButtonSelected" : "BS22TopButtonsNoneSelected"
        default:
            return nil
        }
    }

    private func symbolName(for buttonID: Int) -> String {
        switch buttonID {
        case 0: return "rectangle.lefthalf.inset.filled"
        case 1: return "rectangle.righthalf.inset.filled"
        default: return "button.programmable"
        }
    }

    private func triggerDisplayName(_ action: PFActionType) -> String {
        switch action {
        case .shortSingle, .invalid:
            return "Short Press"
        case .double:
            return "Double Press"
        case .long:
            return "Long Press"
        case .lowToHigh:
            return "Edge Trigger"
        default:
            return "\(action)"
        }
    }
}
