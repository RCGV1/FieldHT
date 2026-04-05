//
//  NotificationManager.swift
//  FieldHT
//

import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    static let lowBatteryCategoryID = "LOW_BATTERY"
    static let enableLowPowerActionID = "ENABLE_LOW_POWER"

    weak var radioManager: RadioManager?
    private var pendingEnableLowPowerAction = false

    private override init() {
        super.init()
    }

    func requestPermission() {
        setupCategories()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted {
                self.setupCategories()
            }
        }
    }

    private func setupCategories() {
        let action = UNNotificationAction(
            identifier: Self.enableLowPowerActionID,
            title: "Enable Low Power Mode",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.lowBatteryCategoryID,
            actions: [action],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func scheduleLowBatteryNotification(level: Int) {
        print("NotificationManager: scheduling low battery notification at \(level)%")
        let content = UNMutableNotificationContent()
        content.title = "Radio Battery Low"
        content.body = "Battery is at \(level)%. Enable Low Power Mode to extend usage."
        content.sound = .default
        content.categoryIdentifier = Self.lowBatteryCategoryID

        let request = UNNotificationRequest(
            identifier: "com.fieldHT.lowBattery",
            content: content,
            trigger: nil // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }

    func performPendingActionsIfNeeded() {
        guard pendingEnableLowPowerAction else { return }
        print("NotificationManager: applying pending low power action")
        pendingEnableLowPowerAction = false
        Task { @MainActor in
            radioManager?.enableLowPowerMode()
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == Self.enableLowPowerActionID {
            print("NotificationManager: low power action tapped")
            pendingEnableLowPowerAction = true
            performPendingActionsIfNeeded()
        }
        completionHandler()
    }
}
