import Foundation

#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
final class SatelliteLiveActivityManager {
    static let shared = SatelliteLiveActivityManager()

    #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ActivityKit)
    private var activity: Activity<SatelliteTrackingAttributes>?
    private var lastUpdateAt: Date?
    #endif

    private init() {}

    var isSupported: Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        return false
        #else
        return false
        #endif
    }

    @discardableResult
    func start(satId: Int, initialState: SatelliteActivityState) -> Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return false }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }

        // End any existing activities (best-effort).
        let oldActivities = Activity<SatelliteTrackingAttributes>.activities
        activity = nil
        lastUpdateAt = nil
        if !oldActivities.isEmpty {
            Task {
                for a in oldActivities {
                    await a.end(nil, dismissalPolicy: .immediate)
                }
            }
        }

        let attrs = SatelliteTrackingAttributes(satId: satId)
        do {
            let state = SatelliteTrackingAttributes.ContentState(from: initialState)
            if #available(iOS 16.2, *) {
                activity = try Activity.request(
                    attributes: attrs,
                    content: .init(state: state, staleDate: nil),
                    pushType: nil
                )
            } else {
                activity = try Activity.request(attributes: attrs, contentState: state, pushType: nil)
            }
            lastUpdateAt = Date()
            return activity != nil
        } catch {
            // Best-effort.
            #if DEBUG
            print("SatelliteLiveActivityManager.start failed: \(error)")
            #endif
            return false
        }
        #else
        _ = satId
        _ = initialState
        return false
        #endif
    }

    func update(state: SatelliteActivityState, minIntervalSeconds: Double = 2.0) {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        guard let activity = resolveCurrentActivity() else { return }
        let contentState = SatelliteTrackingAttributes.ContentState(from: state)

        if let lastUpdateAt, Date().timeIntervalSince(lastUpdateAt) < minIntervalSeconds {
            return
        }

        lastUpdateAt = Date()
        Task {
            await activity.update(.init(state: contentState, staleDate: nil))
        }
        #else
        _ = state
        _ = minIntervalSeconds
        #endif
    }

    func end() async {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        let activities = Activity<SatelliteTrackingAttributes>.activities
        self.activity = nil
        self.lastUpdateAt = nil
        for a in activities {
            await a.end(nil, dismissalPolicy: .immediate)
        }
        #endif
    }

    #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ActivityKit)
    @available(iOS 16.1, *)
    private func resolveCurrentActivity() -> Activity<SatelliteTrackingAttributes>? {
        if let activity { return activity }
        if let existing = Activity<SatelliteTrackingAttributes>.activities.first {
            activity = existing
            return existing
        }
        return nil
    }
    #endif
}
