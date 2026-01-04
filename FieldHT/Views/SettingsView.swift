//
//  SettingsView.swift
//  FieldHT
//
//  Created by Benjamin Faershtein on 12/13/25.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var radioManager: RadioManager
    @StateObject private var viewModel = SettingsViewModel()
    
    @State private var isHydrating = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Group {
                    if !radioManager.isConnected {
                        VStack(spacing: 20) {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("Not Connected")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text("Connect to a radio device to view and edit settings")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.isLoading {
                        ProgressView("Loading settings...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.settings != nil {
                        Form {
                            Section {
                                if let radioController = radioManager.radioController {
                                    NavigationLink(
                                        destination: ChannelListView(radioController: radioController)
                                            .environmentObject(radioManager)
                                    ) {
                                        Label("Channel Configuration", systemImage: "list.number")
                                    }
                                } else {
                                    Label("Channel Configuration", systemImage: "list.number")
                                        .foregroundColor(.secondary)
                                }
                            }
                            // Audio Settings
                            Section("Audio") {
                                VStack(alignment: .leading) {
                                    Text("Squelch Level: \(viewModel.settings?.squelchLevel ?? 0)")
                                    Slider(value: Binding(
                                        get: { Double(viewModel.settings?.squelchLevel ?? 0) },
                                        set: { viewModel.updateSquelchLevel(Int($0)) }
                                    ), in: 0...9, step: 1)
                                }
                                
                                Picker("Mic Gain", selection: Binding(
                                    get: { viewModel.settings?.micGain ?? 0 },
                                    set: { viewModel.updateMicGain($0) }
                                )) {
                                    ForEach(0..<5) { i in
                                        Text("\(i)").tag(i)
                                    }
                                }
                                
                                Picker("BT Mic Gain", selection: Binding(
                                    get: { viewModel.settings?.btMicGain ?? 0 },
                                    set: { viewModel.updateBtMicGain($0) }
                                )) {
                                    ForEach(0..<5) { i in
                                        Text("\(i)").tag(i)
                                    }
                                }
                                
                                Picker("Local Speaker", selection: Binding(
                                    get: { viewModel.settings?.localSpeaker ?? 0 },
                                    set: { viewModel.updateLocalSpeaker($0) }
                                )) {
                                    Text("Internal").tag(0)
                                    Text("External").tag(1)
                                    Text("Both").tag(2)
                                }
                                
                                Picker("HM Speaker", selection: Binding(
                                    get: { viewModel.settings?.hmSpeaker ?? 0 },
                                    set: { viewModel.updateHmSpeaker($0) }
                                )) {
                                    Text("Off").tag(0)
                                    Text("On").tag(1)
                                }
                            }
                            
                            // Transmission Settings
                            Section("Transmission") {
                                VStack(alignment: .leading) {
                                    Text("TX Hold Time: \(viewModel.settings?.txHoldTime ?? 0)s")
                                    Slider(value: Binding(
                                        get: { Double(viewModel.settings?.txHoldTime ?? 0) },
                                        set: { viewModel.updateTxHoldTime(Int($0)) }
                                    ), in: 0...10, step: 1)
                                }
                                
                                VStack(alignment: .leading) {
                                    Text("TX Time Limit: \(viewModel.settings?.txTimeLimit ?? 0)s")
                                    Slider(value: Binding(
                                        get: { Double(viewModel.settings?.txTimeLimit ?? 0) },
                                        set: { viewModel.updateTxTimeLimit(Int($0)) }
                                    ), in: 0...240, step: 30)
                                }
                                
                                Toggle("Tail Eliminator", isOn: Binding(
                                    get: { viewModel.settings?.tailElim ?? false },
                                    set: { viewModel.updateTailElim($0) }
                                ))
                                
                                Toggle("PTT Lock", isOn: Binding(
                                    get: { viewModel.settings?.pttLock ?? false },
                                    set: { viewModel.updatePttLock($0) }
                                ))
                                Toggle(
                                    "Dual Watch",
                                    isOn: Binding(
                                        get: { viewModel.isDualWatchOn },
                                        set: { viewModel.setDualWatch($0) }
                                    )
                                )

                            }
                            
                            // Power Settings
                            Section("Power") {
                                Toggle("Auto Power On", isOn: Binding(
                                    get: { viewModel.settings?.autoPowerOn ?? false },
                                    set: { viewModel.updateAutoPowerOn($0) }
                                ))
                                
                                Picker("Auto Power Off", selection: Binding(
                                    get: { viewModel.settings?.autoPowerOff ?? 0 },
                                    set: { viewModel.updateAutoPowerOff($0) }
                                )) {
                                    Text("Off").tag(0)
                                    Text("Level 1 (Short)").tag(1)
                                    Text("Level 2").tag(2)
                                    Text("Level 3").tag(3)
                                    Text("Level 4 (Medium)").tag(4)
                                    Text("Level 5").tag(5)
                                    Text("Level 6").tag(6)
                                    Text("Level 7 (Long)").tag(7)
                                }
                                
                                Toggle("Power Saving Mode", isOn: Binding(
                                    get: { viewModel.settings?.powerSavingMode ?? false },
                                    set: { viewModel.updatePowerSavingMode($0) }
                                ))
                            }
                            
                            // Display Settings
                            Section("Display") {
                                Picker("Screen Timeout", selection: Binding(
                                    get: { viewModel.settings?.screenTimeout ?? 0 },
                                    set: { viewModel.updateScreenTimeout($0) }
                                )) {
                                    Text("Always On").tag(31)
                                    Text("5s").tag(5)
                                    Text("10s").tag(10)
                                    Text("15s").tag(15)
                                    Text("20s").tag(20)
                                    Text("25s").tag(25)
                                    Text("300s (Max)").tag(300)
                                }
                                
                                Toggle("Imperial Units", isOn: Binding(
                                    get: { viewModel.settings?.imperialUnit ?? false },
                                    set: { viewModel.updateImperialUnit($0) }
                                ))
                            }
                            
                            // Advanced Settings
                            Section("Advanced") {
                                Toggle("Auto Relay", isOn: Binding(
                                    get: { viewModel.settings?.autoRelayEn ?? false },
                                    set: { viewModel.updateAutoRelayEn($0) }
                                ))
                                
                                Toggle("Keep AGHFP Link", isOn: Binding(
                                    get: { viewModel.settings?.keepAghfpLink ?? false },
                                    set: { viewModel.updateKeepAghfpLink($0) }
                                ))
                                
                                Toggle("Adaptive Response", isOn: Binding(
                                    get: { viewModel.settings?.adaptiveResponse ?? false },
                                    set: { viewModel.updateAdaptiveResponse($0) }
                                ))
                                
                                Toggle("Disable Tone", isOn: Binding(
                                    get: { viewModel.settings?.disTone ?? false },
                                    set: { viewModel.updateDisTone($0) }
                                ))
                                
                                Toggle("Use Freq Range 2", isOn: Binding(
                                    get: { viewModel.settings?.useFreqRange2 ?? false },
                                    set: { viewModel.updateUseFreqRange2($0) }
                                ))
                                
                                Toggle("Leading Sync Bit", isOn: Binding(
                                    get: { viewModel.settings?.leadingSyncBitEn ?? false },
                                    set: { viewModel.updateLeadingSyncBitEn($0) }
                                ))
                                
                                Toggle("Pairing at Power On", isOn: Binding(
                                    get: { viewModel.settings?.pairingAtPowerOn ?? false },
                                    set: { viewModel.updatePairingAtPowerOn($0) }
                                ))
                                
                                Toggle("Disable Digital Mute", isOn: Binding(
                                    get: { viewModel.settings?.disDigitalMute ?? false },
                                    set: { viewModel.updateDisDigitalMute($0) }
                                ))
                                
                                Toggle("Signaling ECC Enable", isOn: Binding(
                                    get: { viewModel.settings?.signalingEccEn ?? false },
                                    set: { viewModel.updateSignalingEccEn($0) }
                                ))
                                
                                Toggle("Channel Data Lock", isOn: Binding(
                                    get: { viewModel.settings?.chDataLock ?? false },
                                    set: { viewModel.updateChDataLock($0) }
                                ))
                                
                            }
                        }
                        .disabled(viewModel.isSaving || isHydrating)
                    } else if let error = viewModel.errorMessage {
                        VStack(spacing: 20) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 60))
                                .foregroundColor(.red)
                            Text("Error Loading Settings")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            Button("Retry") {
                                viewModel.retryLoad()
                            }
                            .padding(.top)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Fallback for unknown state
                        VStack(spacing: 20) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 60))
                                .foregroundColor(.orange)
                            Text("Status Unknown")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text("Connected explicitly but no settings data available.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Button("Force Reload") {
                                viewModel.retryLoad()
                            }
                            .padding(.top)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .blur(radius: isHydrating ? 3 : 0)
                
                // Hydration loading overlay
                if isHydrating {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            
                            Text("Syncing with radio...")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .padding(32)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .shadow(radius: 20)
                        )
                    }
                }
            }
            .navigationTitle("Radio Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isSaving {
                        ProgressView()
                    }
                }
            }
            .onChange(of: radioManager.isConnected) { _, isConnected in
                if isConnected {
                    Task {
                        await hydrateRadio()
                    }
                } else {
                    viewModel.setRadioController(nil)
                }
            }
            .onAppear {
                print("SettingsView: onAppear. Connected: \(radioManager.isConnected)")
                if radioManager.isConnected {
                    viewModel.setRadioController(radioManager.radioController)
                }
            }
        }
    }
    
    // Helper function to hydrate radio with loading indicator and retry logic
    private func hydrateRadio() async {
        await MainActor.run {
            isHydrating = true
        }
        
        // Give time for radio to complete initial hydration if just connected
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        let backoffs = [5, 10, 15]
        
        for attempt in 0..<3 {
            do {
                try await radioManager.radioController?.hydrate()
                
                await MainActor.run {
                    if radioManager.isConnected {
                        viewModel.setRadioController(radioManager.radioController)
                    }
                    isHydrating = false
                }
                return // Success
            } catch {
                print("Settings hydration attempt \(attempt + 1) failed: \(error)")
                
                if attempt < backoffs.count {
                    let delaySeconds = backoffs[attempt]
                    let delay = UInt64(delaySeconds) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
        
        await MainActor.run {
            isHydrating = false
            viewModel.errorMessage = "Failed to sync settings with radio after multiple attempts."
        }
    }
}

// Helper view for editable setting rows
struct SettingRow: View {
    let title: String
    @State var value: String
    let onChange: (String) -> Void
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("Value", text: $value)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
                .onChange(of: value) { _, newValue in
                    onChange(newValue)
                }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(RadioManager())
}
