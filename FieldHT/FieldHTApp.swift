//
//  FieldHTApp.swift
//  FieldHT
//
//  Created by Benjamin Faershtein on 1/4/26.
//

import SwiftUI
import Foundation
import UserNotifications
import TipKit

@main
struct FieldHTApp: App {
    @StateObject private var radioManager = RadioManager()
    @StateObject private var radioControlLayout = RadioControlLayoutStore.shared
    @AppStorage("FieldHT.appLanguage") private var appLanguage = "system"
    @Environment(\.scenePhase) private var scenePhase
    private let notificationManager = NotificationManager.shared

    init() {
        UNUserNotificationCenter.current().delegate = notificationManager
        recordAppLaunch()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(radioManager)
                .environmentObject(radioControlLayout)
                .environment(\.locale, appLanguage == "en" ? Locale(identifier: "en") : .current)
                .onAppear {
                    notificationManager.radioManager = radioManager
                    notificationManager.requestPermission()
                    notificationManager.performPendingActionsIfNeeded()
                    RadioIntentBridge.shared.manager = radioManager
                    APRSIGateService.shared.apply(
                        configuration: APRSIGateSettingsStore.shared.configuration,
                        radioController: radioManager.radioController
                    )
                }
            .onChange(of: radioManager.isConnected) { _, _ in
                APRSIGateService.shared.apply(
                    configuration: APRSIGateSettingsStore.shared.configuration,
                    radioController: radioManager.radioController
                )
            }
                .task {
                    try? Tips.configure([
                        .displayFrequency(.immediate)
                    ])
                }
                .onChange(of: scenePhase) { _, newPhase in
                    recordScenePhase(newPhase)
                }
        }
    }

    private func recordAppLaunch() {
        guard BLECaptureStore.isEnabled else { return }

        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info["CFBundleVersion"] as? String ?? "unknown"

        Task {
            await BLECaptureStore.shared.recordNote(
                category: "app_process_launch",
                message: "FieldHT process launched",
                fields: [
                    "pid": String(ProcessInfo.processInfo.processIdentifier),
                    "version": version,
                    "build": build
                ]
            )
        }
    }

    private func recordScenePhase(_ phase: ScenePhase) {
        guard BLECaptureStore.isEnabled else { return }

        let phaseName: String
        switch phase {
        case .active:
            phaseName = "active"
        case .inactive:
            phaseName = "inactive"
        case .background:
            phaseName = "background"
        @unknown default:
            phaseName = "unknown"
        }

        Task {
            await BLECaptureStore.shared.recordNote(
                category: "app_scene_phase",
                message: "App scene phase changed",
                fields: ["phase": phaseName]
            )
        }
    }
}
