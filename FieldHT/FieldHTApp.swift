//
//  FieldHTApp.swift
//  FieldHT
//
//  Created by Benjamin Faershtein on 1/4/26.
//

import SwiftUI
import UserNotifications
import TipKit

@main
struct FieldHTApp: App {
    @StateObject private var radioManager = RadioManager()
    private let notificationManager = NotificationManager()

    init() {
        UNUserNotificationCenter.current().delegate = notificationManager
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(radioManager)
                .onAppear {
                    notificationManager.radioManager = radioManager
                    notificationManager.requestPermission()
                }
                .task {
                    try? Tips.configure([
                        .displayFrequency(.immediate)
                    ])
                }
        }
    }
}
