import Foundation
import Combine
import CoreLocation

// Bring in app types used by this view model.
import SwiftUI

// Satellite helpers used for Doppler/range.
import MapKit

@MainActor
final class SatelliteTrackingViewModel: NSObject, ObservableObject {
    enum TrackingSource: Equatable {
        case unknown
        case offlineFreshTLE
        case offlineStaleTLE
        case onlineN2YO
    }
    enum SortMode: String, CaseIterable, Identifiable {
        case nextPass
        case maxElevation

        var id: String { rawValue }
        var title: String {
            switch self {
            case .nextPass: return "Next pass"
            case .maxElevation: return "Max elevation"
            }
        }
    }

    struct Pass: Equatable {
        let startUTC: Int
        let maxEl: Double
        let maxUTC: Int
        let endUTC: Int
    }

    struct SatelliteRow: Identifiable {
        let id: Int
        let name: String
        let footprintLat: Double
        let footprintLng: Double
        let altitudeKm: Double?
        let elevationDeg: Double?
        var passes: [Pass]?
    }

    @Published var isLocationAuthorized: Bool = false
    @Published var observerLocation: CLLocation?

    @Published var query: String = ""
    @Published var sortMode: SortMode = .nextPass
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    @Published var isLoadingPasses: Bool = false
    @Published var passStatusMessage: String?
    @Published var isMissingN2YOAPIKey: Bool = false
    @Published var n2yoAPIKeyDraft: String = ""

    @Published var isFilteringSupportedSatellites: Bool = false

    @Published var favoriteSatellites: [SatelliteRow] = []
    @Published var nowSoonSatellites: [SatelliteRow] = []
    @Published var selectedSatelliteId: Int?

    @Published var favoriteSatelliteIds: Set<Int> = [25544]
    @Published var discoverSatellites: [SatelliteRow] = []

    // Search/add favorites
    @Published var searchText: String = ""
    @Published var searchResults: [SatelliteRow] = []
    @Published var isSearching: Bool = false

    // Filter for "Discover" and "Now/Soon" lists.
    @Published var minElevationDeg: Double = 5 {
        didSet {
            applyMinElevationFilterToDiscover()
            rebuildNowSoonList()
        }
    }

    @Published var isTracking: Bool = false

    @Published private(set) var trackingSource: TrackingSource = .unknown

    @Published var selectedPositions: [N2YOSatPosition] = []
    @Published var selectedPathPositions: [N2YOSatPosition] = []
    @Published var selectedAzimuth: Double?
    @Published var selectedElevation: Double?
    @Published var selectedRangeKm: Double?
    @Published var selectedAltitudeKm: Double?
    @Published var selectedSatelliteName: String?
    @Published var selectedSatelliteDetailText: String?

    func trackingSourceText() -> String? {
        guard selectedSatelliteId != nil else { return nil }
        switch trackingSource {
        case .unknown:
            return nil
        case .offlineFreshTLE:
            return "Tracking: Cached"
        case .offlineStaleTLE:
            return "Tracking: Cached (stale)"
        case .onlineN2YO:
            return "Tracking: Network"
        }
    }

    // Phone compass heading (degrees). Used for optional map orientation.
    @Published var deviceHeadingDeg: Double?

    @Published var nominalRxMHz: Double = 145.800
    @Published var nominalTxMHz: Double = 145.800
    @Published var dopplerRxMHz: Double?
    @Published var dopplerTxMHz: Double?
    @Published var rangeRateMetersPerSecond: Double?
    @Published var dopplerRxShiftHz: Int?

    @Published private(set) var autoApplyEnabled: Bool = true
    @Published var autoApplyChannel: ChannelType = .a
    @Published var autoApplyMinDeltaHz: Double = 10

    @Published var frequencyOptions: [SatFrequencyOption] = []
    @Published var selectedFrequencyOptionId: String = "custom"
    @Published var isLoadingFrequencies: Bool = false
    @Published var frequencyErrorMessage: String?

    @Published var showAllFrequencyOptions: Bool = false {
        didSet {
            rebuildVisibleFrequencyOptions(preferDefaultForNewSelection: false)
        }
    }

    // If enabled, drive the radio's built-in satellite mode (cmd 35/36/77).
    // This avoids writing VFO channels (cmd 14) during Doppler updates.
    @Published private(set) var syncRadioSatModeEnabled: Bool = true

    private let locationManager = CLLocationManager()
    private let n2yo = N2YOClient()
    private let satnogs = SatNogDBClient()
    private let tleStore = TLEStore()

    private var favoriteNameCache: [Int: String] = [25544: "ISS"]

    private static let pinnedKey = "com.fieldHT.sat.pinnedNoradIds"
    private static let favoritesKey = "com.fieldHT.sat.favoriteNoradIds"
    private var passCache: [Int: [Pass]] = [:]
    private var passCacheLocation: CLLocation?

    private var passFetchInFlightCount: Int = 0

    private var lastAboveRows: [SatelliteRow] = []

    private var supportedSatelliteCache: [Int: Bool] = [:]
    private var supportCheckTask: Task<Void, Never>?
    private var supportRetryAfterUnixById: [Int: Double] = [:]

    private struct SupportCacheEntry: Codable {
        let supported: Bool
        let checkedAtUnix: Double
    }

    private static let supportCacheKey = "com.fieldHT.sat.supportedVhfUhfCache"
    private static let supportCacheTTLSeconds: Double = 14 * 24 * 3600

    private var supportCacheById: [Int: SupportCacheEntry] = [:]

    private var searchTask: Task<Void, Never>?

    private var refreshTask: Task<Void, Never>?
    private var passFetchTask: Task<Void, Never>?

    private var lastPositionsFetchAt: Date?
    private var lastPositionsSatId: Int?
    private var lastPositions: [N2YOSatPosition] = []
    private static let positionsFetchIntervalSeconds: Double = 30
    private static let positionsWindowSeconds: Int = 60

    private static let pathWindowSeconds: Int = 20 * 60
    private static let pathStepSeconds: Int = 10

    private var lastAutoAppliedRxMHz: Double?

    private var lastSatModeSentAt: Date?
    private var lastSatModeSentKey: SatModeKey?
    private var nominalSyncTask: Task<Void, Never>?

    private var liveActivitySatId: Int?

    private var frequencyFetchTask: Task<Void, Never>?
    private var satelliteMetaTask: Task<Void, Never>?

    private var allFrequencyOptions: [SatFrequencyOption] = []
    private var lastToneWriteKey: String?

    private static let defaultFrequencyOptionLimit = 8

    // Use the radio's broader *tunable* VHF/UHF range (not just ham sub-bands).
    // This keeps satellite/transmitter lists relevant without overfitting to a specific region plan.
    private static let supportedTuningRangesMHz: [ClosedRange<Double>] = [
        136.0...174.0,
        400.0...480.0
    ]

    private static func isSupportedTuningMHz(_ mhz: Double) -> Bool {
        supportedTuningRangesMHz.contains(where: { $0.contains(mhz) })
    }

    private static func isCancellationLike(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let e = error as? URLError, e.code == .cancelled { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled { return true }
        return false
    }

    private struct SatModeKey: Equatable {
        let satId: Int
        let rangeKmX10: Int
        let shiftHz: Int
        let azDegX10: Int
        let elDegX10: Int
        let altKmX10: Int
    }

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .none
        df.timeStyle = .short
        return df
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 250

        // Migration: "pinned" -> "favorites".
        let defaults = UserDefaults.standard
        if let arr = defaults.array(forKey: Self.favoritesKey) as? [Int], !arr.isEmpty {
            favoriteSatelliteIds = Set(arr)
            favoriteSatelliteIds.insert(25544)
        } else if let arr = defaults.array(forKey: Self.pinnedKey) as? [Int], !arr.isEmpty {
            favoriteSatelliteIds = Set(arr)
            favoriteSatelliteIds.insert(25544)
            defaults.set(arr, forKey: Self.favoritesKey)
        }

        // Prefer Keychain-backed storage (migrates any legacy UserDefaults value automatically).
        n2yoAPIKeyDraft = N2YOAPIKeyStore.get() ?? ""

        loadSupportCache()
    }

    func setN2YOAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { N2YOAPIKeyStore.clear() }
        else { N2YOAPIKeyStore.set(trimmed) }
        n2yoAPIKeyDraft = trimmed

        // Force a re-fetch on next request.
        passCache.removeAll(keepingCapacity: true)
        passStatusMessage = nil
        isMissingN2YOAPIKey = false
    }

    private func beginPassFetch(clearStatus: Bool) {
        passFetchInFlightCount += 1
        isLoadingPasses = true
        if clearStatus {
            passStatusMessage = nil
            isMissingN2YOAPIKey = false
        }
    }

    private func endPassFetch() {
        passFetchInFlightCount = max(0, passFetchInFlightCount - 1)
        isLoadingPasses = passFetchInFlightCount > 0
    }

    private func loadSupportCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.supportCacheKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([Int: SupportCacheEntry].self, from: data)
            supportCacheById = decoded

            // Populate the fast bool cache with non-stale entries.
            let now = Date().timeIntervalSince1970
            for (id, entry) in decoded {
                if now - entry.checkedAtUnix <= Self.supportCacheTTLSeconds {
                    supportedSatelliteCache[id] = entry.supported
                }
            }
        } catch {
            // Ignore; cache is best-effort.
        }
    }

    private func persistSupportCache() {
        do {
            let data = try JSONEncoder().encode(supportCacheById)
            UserDefaults.standard.set(data, forKey: Self.supportCacheKey)
        } catch {
            // Ignore; cache is best-effort.
        }
    }

    func addFavorite(_ satId: Int, name: String?) {
        favoriteSatelliteIds.insert(satId)
        if let name {
            favoriteNameCache[satId] = name
        }
        persistFavorites()

        // Prefetch TLE so favorites are trackable offline.
        Task { [tleStore] in
            await tleStore.ensureFresh(noradId: satId, fallbackName: name, nowUnix: Date().timeIntervalSince1970)
        }

        Task { await refreshFavorites() }
    }

    // Back-compat with earlier naming.
    func pinSatellite(_ satId: Int, name: String?) {
        addFavorite(satId, name: name)
    }

    func removeFavorite(_ satId: Int) {
        if satId == 25544 { return }
        favoriteSatelliteIds.remove(satId)
        persistFavorites()
        Task { await refreshFavorites() }
    }

    // Back-compat with earlier naming.
    func unpinSatellite(_ satId: Int) {
        removeFavorite(satId)
    }

    private func persistFavorites() {
        let arr = Array(favoriteSatelliteIds)
        UserDefaults.standard.set(arr, forKey: Self.favoritesKey)
    }

    func requestLocationIfNeeded() {
        let status = locationManager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            isLocationAuthorized = true
            locationManager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                locationManager.headingFilter = 1
                locationManager.startUpdatingHeading()
            }
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            isLocationAuthorized = false
            deviceHeadingDeg = nil
        }
    }

    func refreshAbove() {
        guard let obs = observerLocation else { return }
        isLoading = true
        errorMessage = nil

        if let loc = passCacheLocation, loc.distance(from: obs) > 5_000 {
            passCache.removeAll(keepingCapacity: true)
        }
        passCacheLocation = obs

        passFetchTask?.cancel()
        passFetchTask = Task {
            defer { isLoading = false }
            do {
                let above = try await n2yo.above(
                    observerLat: obs.coordinate.latitude,
                    observerLng: obs.coordinate.longitude,
                    observerAltMeters: obs.altitude,
                    searchRadiusDeg: 90,
                    categoryId: 18
                )

                let rows: [SatelliteRow] = above.above.map { sat in
                    let el = Self.estimateElevationDeg(
                        observer: obs,
                        satLat: sat.satlat,
                        satLng: sat.satlng,
                        satAltitudeKm: sat.satalt
                    )
                    return SatelliteRow(
                        id: sat.satid,
                        name: sat.satname,
                        footprintLat: sat.satlat,
                        footprintLng: sat.satlng,
                        altitudeKm: sat.satalt,
                        elevationDeg: el,
                        passes: passCache[sat.satid]
                    )
                }

                lastAboveRows = rows
                applyMinElevationFilterToDiscover()
                scheduleSupportChecks(for: rows)

                for r in rows {
                    // Keep a nicer UI label for ISS.
                    if r.id == 25544 {
                        continue
                    }
                    favoriteNameCache[r.id] = r.name
                }

                await refreshFavorites()
                rebuildNowSoonList()
            } catch {
                // Avoid showing cancellations as user-visible errors.
                if Self.isCancellationLike(error) { return }
                // Best-effort only; keep UI calm even when networking is flaky.
            }
        }
    }

    func refreshFavorites() async {
        guard let obs = observerLocation else { return }

        let ids = Array(favoriteSatelliteIds).sorted()

        var rows: [SatelliteRow] = []
        rows.reserveCapacity(ids.count)

        for id in ids {
            let name = favoriteNameCache[id] ?? discoverSatellites.first(where: { $0.id == id })?.name ?? "NORAD \(id)"
            let cachedPass = passCache[id]
            rows.append(SatelliteRow(id: id, name: name, footprintLat: 0, footprintLng: 0, altitudeKm: nil, elevationDeg: nil, passes: cachedPass))

            // Prefetch TLE for favorites so we can track without cell reception later.
            await tleStore.ensureFresh(noradId: id, fallbackName: name, nowUnix: Date().timeIntervalSince1970)
        }

        favoriteSatellites = rows

        // Fetch pass summaries best-effort.
        beginPassFetch(clearStatus: true)
        defer { endPassFetch() }
        do {
            for sat in rows {
                if Task.isCancelled { return }
                if passCache[sat.id] != nil { continue }
                let passes = try await n2yo.radioPasses(
                    satId: sat.id,
                    observerLat: obs.coordinate.latitude,
                    observerLng: obs.coordinate.longitude,
                    observerAltMeters: obs.altitude,
                    days: 1,
                    minElevationDeg: Int(minElevationDeg.rounded())
                )

                let mapped = Array(passes.passes.prefix(3)).map {
                    Pass(startUTC: $0.startUTC, maxEl: $0.maxEl, maxUTC: $0.maxUTC, endUTC: $0.endUTC)
                }
                if !mapped.isEmpty {
                    passCache[sat.id] = mapped
                    updatePassesInLists(satId: sat.id, passes: mapped)
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        } catch {
            if Self.isCancellationLike(error) { return }
            if let e = error as? N2YOClientError, case .missingAPIKey = e {
                isMissingN2YOAPIKey = true
            }
            passStatusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        // Sort by next pass.
        favoriteSatellites.sort {
            let a = $0.passes?.first?.startUTC ?? Int.max
            let b = $1.passes?.first?.startUTC ?? Int.max
            if a != b { return a < b }
            return $0.name < $1.name
        }

        rebuildNowSoonList()
    }

    func selectSatellite(_ satId: Int, name: String?) {
        selectedSatelliteId = satId
        trackingSource = .unknown

        let satName = name ?? favoriteNameCache[satId] ?? lastAboveRows.first(where: { $0.id == satId })?.name
        if let satName {
            favoriteNameCache[satId] = satName
            selectedSatelliteName = satName
        } else {
            selectedSatelliteName = nil
        }

        loadSatelliteMetaFromSatNOGS(noradId: satId)
        loadFrequencyOptionsFromSatNOGS(for: satId, name: satName, preferDefaultForNewSelection: true)

        // Best-effort: fetch TLE so offline tracking can take over.
        Task { [tleStore] in
            await tleStore.ensureFresh(noradId: satId, fallbackName: satName, nowUnix: Date().timeIntervalSince1970)
        }

        if passCache[satId] == nil {
            Task { [weak self] in
                await self?.fetchPassForSatellite(satId)
            }
        }
    }

    func onFrequencyOptionChanged(radioManager: RadioManager) {
        applySelectedFrequencyOptionToNominal()
        scheduleFreqModeParameterSync(radioManager: radioManager)
        maybeSendSatModeInfo(radioManager: radioManager, force: true)

        // Force a tone write for the new selection when possible.
        lastToneWriteKey = nil

        // Push the new selection immediately when we can.
        if radioManager.isConnected, dopplerRxMHz != nil {
            let applyChannel: ChannelType = syncRadioSatModeEnabled ? ((radioManager.activeChannel == .off) ? .a : radioManager.activeChannel) : autoApplyChannel
            applyDopplerToRadio(applyChannel, radioManager: radioManager)
        }
    }

    func startTrackingSelected() {
        guard selectedSatelliteId != nil else { return }
        isTracking = true
        trackingSource = .unknown
        startLiveActivityIfPossible()
        startSelectedRefreshLoop()
    }

    func stopTracking() {
        isTracking = false
        refreshTask?.cancel()
        refreshTask = nil

        trackingSource = .unknown

        selectedPathPositions = []

        endLiveActivity()

        // Don't leave a scary red error when the user stops/switches.
        errorMessage = nil
    }

    func stop() {
        stopTracking()

        passFetchTask?.cancel()
        passFetchTask = nil

        nominalSyncTask?.cancel()
        nominalSyncTask = nil

        frequencyFetchTask?.cancel()
        frequencyFetchTask = nil

        satelliteMetaTask?.cancel()
        satelliteMetaTask = nil

        supportCheckTask?.cancel()
        supportCheckTask = nil

        // If we cancel support checks while the UI is showing a spinner, clear it immediately.
        isFilteringSupportedSatellites = false
    }

    func applyDopplerToRadio(_ channel: ChannelType, radioManager: RadioManager) {
        guard let rx = dopplerRxMHz, let tx = dopplerTxMHz else { return }

        if shouldUseRadioSatMode(radioManager: radioManager) {
            // Drive the radio's built-in satellite mode (cmd 35/36/77) instead of writing VFO channels.
            let tones = selectedTonesFromFrequencyOption()
            maybeSendSatModeInfo(radioManager: radioManager, force: true)
            radioManager.setFreqModeParameters(rxMHz: rx, txMHz: tx, rxCTCSSHz: tones.rx, txCTCSSHz: tones.tx)
            return
        }

        // VFO apply (split if available), also applying tones when present.
        let tones = selectedTonesFromFrequencyOption()
        radioManager.setSplitFrequencyAndCTCSS(
            rxMHz: rx,
            txMHz: tx,
            rxCTCSSHz: tones.rx,
            txCTCSSHz: tones.tx,
            for: channel
        )
    }

    func onDopplerUpdated(radioManager: RadioManager) {
        guard radioManager.isConnected else { return }
        guard let rx = dopplerRxMHz else { return }

        if shouldUseRadioSatMode(radioManager: radioManager) {
            maybeSendSatModeInfo(radioManager: radioManager)

            // If auto-apply is enabled, update satellite-mode RX/TX parameters (cmd 35/36).
            if autoApplyEnabled, let tx = dopplerTxMHz {
                if let last = lastAutoAppliedRxMHz {
                    let deltaHz = abs(rx - last) * 1_000_000.0
                    if deltaHz < autoApplyMinDeltaHz {
                        return
                    }
                }
                lastAutoAppliedRxMHz = rx
                let tones = selectedTonesFromFrequencyOption()
                radioManager.setFreqModeParameters(rxMHz: rx, txMHz: tx, rxCTCSSHz: tones.rx, txCTCSSHz: tones.tx)
            }
            return
        }

        guard autoApplyEnabled else { return }

        if let last = lastAutoAppliedRxMHz {
            let deltaHz = abs(rx - last) * 1_000_000.0
            if deltaHz < autoApplyMinDeltaHz {
                return
            }
        }

        lastAutoAppliedRxMHz = rx
        let tones = selectedTonesFromFrequencyOption()
        let tx = dopplerTxMHz ?? nominalTxMHz
        radioManager.setSplitFrequencyAndCTCSS(
            rxMHz: rx,
            txMHz: tx,
            rxCTCSSHz: tones.rx,
            txCTCSSHz: tones.tx,
            for: autoApplyChannel
        )
    }

    func onSelectionChanged(radioManager: RadioManager) {
        guard radioManager.isConnected else { return }
        if shouldUseRadioSatMode(radioManager: radioManager) {
            maybeSendSatModeInfo(radioManager: radioManager, force: true)
            sendFreqModeParametersNow(radioManager: radioManager)
            return
        }

        // If we aren't using the radio's satellite mode, push a VFO write immediately so
        // split + tones take effect together.
        let applyChannel: ChannelType = (radioManager.activeChannel == .off) ? .a : radioManager.activeChannel
        applyDopplerToRadio(applyChannel, radioManager: radioManager)
    }

    func scheduleFreqModeParameterSync(radioManager: RadioManager) {
        guard shouldUseRadioSatMode(radioManager: radioManager) else { return }
        guard radioManager.isConnected else { return }

        nominalSyncTask?.cancel()
        nominalSyncTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            self.sendFreqModeParametersNow(radioManager: radioManager)
        }
    }

    func applySortAndFilter() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var filtered = lastAboveRows
        if !q.isEmpty {
            filtered = filtered.filter { $0.name.lowercased().contains(q) || String($0.id).contains(q) }
        }

        switch sortMode {
        case .nextPass:
            filtered.sort {
                let a = $0.passes?.first?.startUTC ?? Int.max
                let b = $1.passes?.first?.startUTC ?? Int.max
                if a != b { return a < b }
                return $0.name < $1.name
            }
        case .maxElevation:
            filtered.sort {
                let a = $0.passes?.first?.maxEl ?? -1
                let b = $1.passes?.first?.maxEl ?? -1
                if a != b { return a > b }
                return $0.name < $1.name
            }
        }

        lastAboveRows = filtered
        applyMinElevationFilterToDiscover()
        rebuildNowSoonList()
    }

    func passText(for sat: SatelliteRow) -> String {
        guard let passes = sat.passes, let first = passes.first else {
            if let el = sat.elevationDeg, el.isFinite {
                return String(format: "Above horizon  El %.0f deg", el)
            }
            return "NORAD \(sat.id)"
        }

        let start = Date(timeIntervalSince1970: TimeInterval(first.startUTC))
        let maxDate = Date(timeIntervalSince1970: TimeInterval(first.maxUTC))
        let end = Date(timeIntervalSince1970: TimeInterval(first.endUTC))

        let durMinutes = Swift.max(0, (first.endUTC - first.startUTC) / 60)
        let startText = formatDate(start)
        let maxText = Self.timeFormatter.string(from: maxDate)
        let endText = Self.timeFormatter.string(from: end)

        var suffix = ""
        if passes.count > 1 {
            let nextBits = passes.dropFirst().prefix(2).map { p in
                let d = Date(timeIntervalSince1970: TimeInterval(p.startUTC))
                return Self.timeFormatter.string(from: d)
            }
            if !nextBits.isEmpty {
                suffix = "  Next: " + nextBits.joined(separator: ", ")
            }
        }

        return String(format: "Next: %@  MaxEl: %.0f deg  (%@-%@, %dm)%@", startText, first.maxEl, maxText, endText, durMinutes, suffix)
    }

    // MARK: - Private

    private func startSelectedRefreshLoop() {
        guard isTracking else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshSelected()
                // Fast UI updates; network calls are throttled inside refreshSelected().
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func refreshSelected() async {
        guard let obs = observerLocation, let satId = selectedSatelliteId else { return }

        let now = Date()

        // Prefer offline propagation if we have a TLE cached.
        // Use fresh TLE when possible, but fall back to stale TLE for offline usefulness.
        let fresh = await tleStore.cachedFreshRecord(noradId: satId, nowUnix: now.timeIntervalSince1970)
        let stale: TLERecord?
        if fresh == nil {
            stale = await tleStore.cachedRecord(noradId: satId)
        } else {
            stale = nil
        }
        if let tle = fresh ?? stale {
            do {
                let start = now
                let offline = try OfflineTLEPropagator.positions(
                    tle: tle,
                    observer: obs,
                    start: start,
                    seconds: Self.positionsWindowSeconds
                )

                let offlinePath = try OfflineTLEPropagator.positionsSampled(
                    tle: tle,
                    observer: obs,
                    start: start,
                    seconds: Self.pathWindowSeconds,
                    stepSeconds: Self.pathStepSeconds
                )
                let mapped: [N2YOSatPosition] = offline.map {
                    N2YOSatPosition(
                        satlatitude: $0.latDeg,
                        satlongitude: $0.lonDeg,
                        sataltitude: $0.altKm,
                        azimuth: $0.azDeg,
                        elevation: $0.elDeg,
                        ra: nil,
                        dec: nil,
                        timestamp: $0.timestamp
                    )
                }

                let mappedPath: [N2YOSatPosition] = offlinePath.map {
                    N2YOSatPosition(
                        satlatitude: $0.latDeg,
                        satlongitude: $0.lonDeg,
                        sataltitude: $0.altKm,
                        azimuth: $0.azDeg,
                        elevation: $0.elDeg,
                        ra: nil,
                        dec: nil,
                        timestamp: $0.timestamp
                    )
                }

                selectedPositions = mapped
                selectedPathPositions = mappedPath
                trackingSource = (fresh != nil) ? .offlineFreshTLE : .offlineStaleTLE
                lastPositionsFetchAt = start
                lastPositionsSatId = satId
                lastPositions = mapped

                if let first = mapped.first {
                    selectedAzimuth = first.azimuth
                    selectedElevation = first.elevation
                    selectedAltitudeKm = first.sataltitude
                    selectedRangeKm = Doppler.slantRangeMeters(observer: obs, sat: first) / 1000.0
                }

                if let rr = Doppler.estimateRangeRateMetersPerSecond(observer: obs, positions: mapped) {
                    rangeRateMetersPerSecond = rr
                    let corr = Doppler.correction(
                        nominalRxHz: nominalRxMHz * 1_000_000.0,
                        nominalTxHz: nominalTxMHz * 1_000_000.0,
                        rangeRateMetersPerSecond: rr
                    )
                    dopplerRxMHz = corr.rxCorrectedHz / 1_000_000.0
                    dopplerTxMHz = corr.txCorrectedHz / 1_000_000.0

                    let shift = corr.rxCorrectedHz - (nominalRxMHz * 1_000_000.0)
                    dopplerRxShiftHz = Int(shift.rounded())
                }

                updateLiveActivityIfPossible(now: now)
                return
            } catch {
                // Fall back to N2YO if propagation fails.
            }
        }

        // No offline TLE available: don't show a misleading long path.
        selectedPathPositions = []

        // Kick a background fetch so offline mode can take over soon.
        let fallbackName = favoriteNameCache[satId] ?? lastAboveRows.first(where: { $0.id == satId })?.name
        await tleStore.ensureFresh(noradId: satId, fallbackName: fallbackName, nowUnix: now.timeIntervalSince1970)

        // Throttle N2YO positions calls to avoid rate limits. Between fetches, reuse the
        // last predicted window so Doppler updates keep flowing without additional API hits.
        if let lastAt = lastPositionsFetchAt,
           lastPositionsSatId == satId,
           now.timeIntervalSince(lastAt) < Self.positionsFetchIntervalSeconds,
           !lastPositions.isEmpty {
            selectedPositions = lastPositions
            trackingSource = .onlineN2YO
            if let first = lastPositions.first {
                selectedAzimuth = first.azimuth
                selectedElevation = first.elevation
                selectedAltitudeKm = first.sataltitude
                selectedRangeKm = Doppler.slantRangeMeters(observer: obs, sat: first) / 1000.0
            }
            if let rr = Doppler.estimateRangeRateMetersPerSecond(observer: obs, positions: lastPositions) {
                rangeRateMetersPerSecond = rr
                let corr = Doppler.correction(
                    nominalRxHz: nominalRxMHz * 1_000_000.0,
                    nominalTxHz: nominalTxMHz * 1_000_000.0,
                    rangeRateMetersPerSecond: rr
                )
                dopplerRxMHz = corr.rxCorrectedHz / 1_000_000.0
                dopplerTxMHz = corr.txCorrectedHz / 1_000_000.0

                let shift = corr.rxCorrectedHz - (nominalRxMHz * 1_000_000.0)
                dopplerRxShiftHz = Int(shift.rounded())
            }

            updateLiveActivityIfPossible(now: now)
            return
        }

        do {
            let resp = try await n2yo.positions(
                satId: satId,
                observerLat: obs.coordinate.latitude,
                observerLng: obs.coordinate.longitude,
                observerAltMeters: obs.altitude,
                seconds: Self.positionsWindowSeconds
            )
            selectedPositions = resp.positions
            trackingSource = .onlineN2YO

            lastPositionsFetchAt = now
            lastPositionsSatId = satId
            lastPositions = resp.positions

            if let first = resp.positions.first {
                selectedAzimuth = first.azimuth
                selectedElevation = first.elevation
                selectedAltitudeKm = first.sataltitude
                selectedRangeKm = Doppler.slantRangeMeters(observer: obs, sat: first) / 1000.0
            }

            if let rr = Doppler.estimateRangeRateMetersPerSecond(observer: obs, positions: resp.positions) {
                rangeRateMetersPerSecond = rr
                let corr = Doppler.correction(
                    nominalRxHz: nominalRxMHz * 1_000_000.0,
                    nominalTxHz: nominalTxMHz * 1_000_000.0,
                    rangeRateMetersPerSecond: rr
                )
                dopplerRxMHz = corr.rxCorrectedHz / 1_000_000.0
                dopplerTxMHz = corr.txCorrectedHz / 1_000_000.0

                let shift = corr.rxCorrectedHz - (nominalRxMHz * 1_000_000.0)
                dopplerRxShiftHz = Int(shift.rounded())
            }

            updateLiveActivityIfPossible(now: now)
        } catch {
            if Self.isCancellationLike(error) { return }
            // Silent while looping; keep last good data.
        }
    }

    // MARK: - Live Activity (best-effort)

    private func startLiveActivityIfPossible(now: Date = Date()) {
        guard let satId = selectedSatelliteId else { return }
        guard SatelliteLiveActivityManager.shared.isSupported else { return }
        guard let initial = makeLiveActivityState(now: now) else {
            return
        }
        liveActivitySatId = satId
        SatelliteLiveActivityManager.shared.start(satId: satId, initialState: initial)
    }

    private func updateLiveActivityIfPossible(now: Date = Date()) {
        guard isTracking else { return }
        guard SatelliteLiveActivityManager.shared.isSupported else { return }
        guard let satId = selectedSatelliteId else { return }
        guard let state = makeLiveActivityState(now: now) else { return }

        // Tracking may have started before we had enough data to populate an activity state.
        if liveActivitySatId == nil || liveActivitySatId != satId {
            liveActivitySatId = satId
            SatelliteLiveActivityManager.shared.start(satId: satId, initialState: state)
        }

        SatelliteLiveActivityManager.shared.update(state: state, minIntervalSeconds: 2.0)
    }

    private func endLiveActivity() {
        liveActivitySatId = nil
        Task { await SatelliteLiveActivityManager.shared.end() }
    }

    private func makeLiveActivityState(now: Date) -> SatelliteActivityState? {
        guard let satId = selectedSatelliteId else { return nil }
        let name = selectedSatelliteName
            ?? favoriteNameCache[satId]
            ?? lastAboveRows.first(where: { $0.id == satId })?.name
            ?? "NORAD \(satId)"

        guard let az = selectedAzimuth,
              let el = selectedElevation,
              let rangeKm = selectedRangeKm else {
            return nil
        }

        let (rx, tx) = currentRxTxForSync()
        let rxX1000 = Self.mhzToX1000(rx)
        let txX1000 = Self.mhzToX1000(tx)

        let shiftHz = dopplerRxShiftHz ?? 0

        return SatelliteActivityState(
            name: name,
            azDeg: Int(az.rounded()),
            elDeg: Int(el.rounded()),
            rangeKm: Int(rangeKm.rounded()),
            dopplerShiftHz: shiftHz,
            rxMHzX1000: rxX1000,
            txMHzX1000: txX1000,
            source: trackingSourceShortText(),
            countdown: trackingCountdownText(now: now),
            updatedAtUnix: Int(now.timeIntervalSince1970)
        )
    }

    private func trackingSourceShortText() -> String {
        switch trackingSource {
        case .offlineFreshTLE:
            return "Cache"
        case .offlineStaleTLE:
            return "Cache"
        case .onlineN2YO:
            return "Net"
        case .unknown:
            return ""
        }
    }

    private static func mhzToX1000(_ mhz: Double) -> Int {
        Int((mhz * 1000.0).rounded())
    }

    private func sendFreqModeParametersNow(radioManager: RadioManager) {
        guard shouldUseRadioSatMode(radioManager: radioManager) else { return }
        let (rx, tx) = currentRxTxForSync()
        let tones = selectedTonesFromFrequencyOption()
        radioManager.setFreqModeParameters(rxMHz: rx, txMHz: tx, rxCTCSSHz: tones.rx, txCTCSSHz: tones.tx)
    }

    private func currentRxTxForSync() -> (rx: Double, tx: Double) {
        if let rx = dopplerRxMHz, let tx = dopplerTxMHz {
            return (rx, tx)
        }
        return (nominalRxMHz, nominalTxMHz)
    }

    private func applyTonesToActiveVFOIfNeeded(radioManager: RadioManager, rxMHz: Double, txMHz: Double) {
        let tones = selectedTonesFromFrequencyOption()
        // Guard: we need valid tones AND a real satellite option (not "custom")
        guard selectedFrequencyOptionId != "custom",
              (tones.rx != nil && tones.rx! > 0) || (tones.tx != nil && tones.tx! > 0) else {
            return
        }

        let applyChannel: ChannelType = (radioManager.activeChannel == .off) ? .a : radioManager.activeChannel
        let satId = selectedSatelliteId ?? -1
        let key = String(format: "sat=%d|opt=%@|ch=%@|rx=%.1f|tx=%.1f", satId, selectedFrequencyOptionId, applyChannel.rawValue, tones.rx ?? -1, tones.tx ?? -1)
        if key == lastToneWriteKey { return }
        lastToneWriteKey = key

        radioManager.setSplitFrequencyAndCTCSS(
            rxMHz: rxMHz,
            txMHz: txMHz,
            rxCTCSSHz: tones.rx,
            txCTCSSHz: tones.tx,
            for: applyChannel
        )
    }

    private func maybeSendSatModeInfo(radioManager: RadioManager, force: Bool = false) {
        guard shouldUseRadioSatMode(radioManager: radioManager) else { return }
        guard let satId = selectedSatelliteId,
              let satName = favoriteNameCache[satId] ?? lastAboveRows.first(where: { $0.id == satId })?.name,
              let rangeKm = selectedRangeKm,
              let shiftHz = dopplerRxShiftHz,
              let az = selectedAzimuth,
              let el = selectedElevation,
              let altKm = selectedAltitudeKm else {
            return
        }

        let now = Date()
        if !force, let lastAt = lastSatModeSentAt, now.timeIntervalSince(lastAt) < 1.0 {
            return
        }

        let key = SatModeKey(
            satId: satId,
            rangeKmX10: Int((rangeKm * 10.0).rounded()),
            shiftHz: shiftHz,
            azDegX10: Int((az * 10.0).rounded()),
            elDegX10: Int((el * 10.0).rounded()),
            altKmX10: Int((altKm * 10.0).rounded())
        )
        if !force, key == lastSatModeSentKey {
            return
        }

        lastSatModeSentAt = now
        lastSatModeSentKey = key
        radioManager.setSatModeInfo(
            name: satName,
            rangeKm: rangeKm,
            dopplerShiftHz: shiftHz,
            azimuthDeg: az,
            elevationDeg: el,
            altitudeKm: altKm
        )
    }

    private func loadFrequencyOptionsFromSatNOGS(for satId: Int, name: String?, preferDefaultForNewSelection: Bool) {
        frequencyFetchTask?.cancel()

        // Keep Custom available even if network fails.
        allFrequencyOptions = []
        rebuildVisibleFrequencyOptions(preferDefaultForNewSelection: preferDefaultForNewSelection)
        frequencyErrorMessage = nil
        isLoadingFrequencies = true

        frequencyFetchTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isLoadingFrequencies = false }

            do {
                let txs = try await satnogs.transmitters(noradId: satId)
                let options = Self.frequencyOptions(from: Self.transmittersForFrequencyOptions(txs, satNoradId: satId))
                if options.isEmpty {
                    self.frequencyErrorMessage = "No supported VHF/UHF frequencies for \(name ?? String(satId))"
                }

                self.allFrequencyOptions = options

                if preferDefaultForNewSelection {
                    if let preferredId = Self.preferredDefaultFrequencyOptionId(for: satId, options: options) {
                        self.selectedFrequencyOptionId = preferredId
                    } else {
                        self.selectedFrequencyOptionId = options.first?.id ?? "custom"
                    }
                }

                self.rebuildVisibleFrequencyOptions(preferDefaultForNewSelection: false)

                self.applySelectedFrequencyOptionToNominal()
            } catch {
                if Self.isCancellationLike(error) { return }
                self.frequencyErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func loadSatelliteMetaFromSatNOGS(noradId: Int) {
        satelliteMetaTask?.cancel()
        selectedSatelliteDetailText = nil

        satelliteMetaTask = Task { [weak self] in
            guard let self else { return }
            do {
                let sats = try await satnogs.satellitesByNorad(noradId)
                guard let sat = sats.first else { return }

                var bits: [String] = []

                if let launched = sat.launched, let year = Self.yearFromISOString(launched) {
                    bits.append("Launched \(year)")
                }
                if let countries = sat.countries?.trimmingCharacters(in: .whitespacesAndNewlines), !countries.isEmpty {
                    bits.append(countries)
                }

                var out = bits.joined(separator: " • ")

                if let otherNames = sat.names?.trimmingCharacters(in: .whitespacesAndNewlines), !otherNames.isEmpty {
                    let cleaned = otherNames.replacingOccurrences(of: "\n", with: ", ")
                    if !cleaned.isEmpty {
                        out = out.isEmpty ? ("Also: " + cleaned) : (out + "\nAlso: " + cleaned)
                    }
                }

                if !out.isEmpty {
                    self.selectedSatelliteDetailText = out
                }
            } catch {
                if Self.isCancellationLike(error) { return }
                // Best-effort only; keep UI clean.
            }
        }
    }

    private static func yearFromISOString(_ iso: String) -> String? {
        // Example: 1998-11-20T00:00:00Z
        let trimmed = iso.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return nil }
        return String(trimmed.prefix(4))
    }

    private func scheduleSupportChecks(for rows: [SatelliteRow]) {
        supportCheckTask?.cancel()

        // No spinner: we keep the UI responsive by running these checks silently.

        let nowUnix = Date().timeIntervalSince1970

        let ids = rows.map(\.id)
        let toCheck = ids.filter {
            if supportedSatelliteCache[$0] != nil { return false }
            if let retryAfter = supportRetryAfterUnixById[$0], nowUnix < retryAfter { return false }
            return true
        }
        guard !toCheck.isEmpty else { return }

        supportCheckTask = Task { [weak self] in
            guard let self else { return }

            for id in toCheck {
                if Task.isCancelled { return }
                do {
                    let txs = try await satnogs.transmitters(noradId: id)
                    let opts = Self.frequencyOptions(from: Self.transmittersForFrequencyOptions(txs, satNoradId: id))
                    let supported = !opts.isEmpty
                    supportedSatelliteCache[id] = supported
                    supportCacheById[id] = SupportCacheEntry(supported: supported, checkedAtUnix: Date().timeIntervalSince1970)
                } catch {
                    if Self.isCancellationLike(error) { return }
                    // Verified-only lists: if we can't determine support, keep as unknown (hidden)
                    // and back off retries to avoid hammering the API.
                    supportRetryAfterUnixById[id] = Date().timeIntervalSince1970 + (30 * 60)
                }

                applyMinElevationFilterToDiscover()
                rebuildNowSoonList()

                // Persist incrementally so we get offline benefit even if the task cancels.
                persistSupportCache()

                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    // MARK: - Search / Add Favorites

    private static func searchScore(name: String, id: Int, query: String) -> Int {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return 0 }

        let n = name.lowercased()
        let idText = String(id)

        var score = 0

        // NORAD id matches.
        if idText == q { score = max(score, 1200) }
        else if idText.hasPrefix(q) { score = max(score, 1100) }
        else if idText.contains(q) { score = max(score, 1000) }

        // Name matches.
        if n == q { score = max(score, 900) }
        else if n.hasPrefix(q) { score = max(score, 800) }
        else if n.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(q) }) {
            score = max(score, 750)
        } else if n.contains(q) { score = max(score, 700) }

        // Shorter names are usually better matches.
        score -= min(40, n.count / 4)
        return score
    }

    private func sortSearchResults(_ rows: [SatelliteRow], query: String) -> [SatelliteRow] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows.sorted { a, b in
            let aFav = favoriteSatelliteIds.contains(a.id)
            let bFav = favoriteSatelliteIds.contains(b.id)

            let aScore = Self.searchScore(name: a.name, id: a.id, query: q) + (aFav ? 200 : 0)
            let bScore = Self.searchScore(name: b.name, id: b.id, query: q) + (bFav ? 200 : 0)

            if aScore != bScore { return aScore > bScore }
            if aFav != bFav { return aFav && !bFav }
            if a.name != b.name { return a.name < b.name }
            return a.id < b.id
        }
    }

    func updateSearch(_ text: String) {
        searchText = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        searchTask?.cancel()

        if trimmed.isEmpty {
            searchResults = []
            isSearching = false
            return
        }

        // Instant local match for anything we already know.
        let local = lastAboveRows + favoriteSatellites + discoverSatellites
        if !local.isEmpty {
            var byId: [Int: SatelliteRow] = [:]
            byId.reserveCapacity(local.count)

            for r in local {
                let score = Self.searchScore(name: r.name, id: r.id, query: trimmed)
                if score <= 0 { continue }
                if let existing = byId[r.id] {
                    let existingScore = Self.searchScore(name: existing.name, id: existing.id, query: trimmed)
                    if score > existingScore { byId[r.id] = r }
                } else {
                    byId[r.id] = r
                }
            }

            let sorted = sortSearchResults(Array(byId.values), query: trimmed)
            searchResults = Array(sorted.prefix(25))
        }

        // Debounced network search (SatNOGS) for new satellites.
        if trimmed.count < 2 {
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }

            let query = trimmed

            defer { self.isSearching = false }

            do {
                let sats = try await satnogs.satellites(search: trimmed, limit: 25)
                var mapped: [SatelliteRow] = sats.compactMap { s in
                    guard let norad = s.noradCatId else { return nil }
                    let name = (s.name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                        ?? "NORAD \(norad)"
                    return SatelliteRow(id: norad, name: name, footprintLat: 0, footprintLng: 0, altitudeKm: nil, elevationDeg: nil, passes: self.passCache[norad])
                }

                // Ensure results are relevant even if server-side filtering is broken.
                mapped = mapped.filter { Self.searchScore(name: $0.name, id: $0.id, query: query) > 0 }

                // Drop stale responses if the user kept typing.
                if self.searchText.trimmingCharacters(in: .whitespacesAndNewlines) != query {
                    return
                }

                // Merge with existing results, keep best match.
                var byId: [Int: SatelliteRow] = [:]
                for r in self.searchResults { byId[r.id] = r }
                for r in mapped {
                    if let existing = byId[r.id] {
                        let a = Self.searchScore(name: existing.name, id: existing.id, query: trimmed)
                        let b = Self.searchScore(name: r.name, id: r.id, query: trimmed)
                        if b > a { byId[r.id] = r }
                    } else {
                        byId[r.id] = r
                    }
                }

                let merged = self.sortSearchResults(Array(byId.values), query: trimmed)
                self.searchResults = Array(merged.prefix(25))
            } catch {
                // Best-effort; keep whatever local results we had.
            }
        }
    }

    func warmSatelliteSearchIndex() {
        Task { [satnogs] in
            _ = try? await satnogs.allSatellites()
        }
    }

    func addFavoriteFromSearch(_ sat: SatelliteRow) {
        addFavorite(sat.id, name: sat.name)
    }

    private func shouldUseRadioSatMode(radioManager: RadioManager) -> Bool {
        guard syncRadioSatModeEnabled else { return false }
        return true
    }

    private func rebuildVisibleFrequencyOptions(preferDefaultForNewSelection: Bool) {
        let limit = Self.defaultFrequencyOptionLimit

        var visible = showAllFrequencyOptions ? allFrequencyOptions : Array(allFrequencyOptions.prefix(limit))
        if selectedFrequencyOptionId != "custom",
           let sel = allFrequencyOptions.first(where: { $0.id == selectedFrequencyOptionId }),
           !visible.contains(sel) {
            visible.insert(sel, at: 0)
        }

        let custom = SatFrequencyOption(
            id: "custom",
            title: "Custom",
            rxMHz: nominalRxMHz,
            txMHz: nominalTxMHz,
            rxCTCSSHz: nil,
            txCTCSSHz: nil,
            isCustom: true
        )

        let finalOptions = visible + [custom]
        frequencyOptions = finalOptions

        // Intentionally quiet: called frequently while editing.

        if preferDefaultForNewSelection {
            selectedFrequencyOptionId = visible.first?.id ?? "custom"
            return
        }
        if frequencyOptions.contains(where: { $0.id == selectedFrequencyOptionId }) {
            return
        }
        selectedFrequencyOptionId = visible.first?.id ?? "custom"
    }

    var hasMoreFrequencyOptions: Bool {
        allFrequencyOptions.count > Self.defaultFrequencyOptionLimit
    }

    private func applySelectedFrequencyOptionToNominal() {
        guard let selected = frequencyOptions.first(where: { $0.id == selectedFrequencyOptionId }) else { return }
        guard !selected.isCustom else { return }
        if let rx = selected.rxMHz {
            nominalRxMHz = rx
        } else if let tx = selected.txMHz {
            // Keep things usable for Doppler and sat-mode writes.
            nominalRxMHz = tx
        }

        if let tx = selected.txMHz {
            nominalTxMHz = tx
        } else if let rx = selected.rxMHz {
            nominalTxMHz = rx
        }
    }

    private static func frequencyOptions(from transmitters: [SatNogTransmitter]) -> [SatFrequencyOption] {
        func hzToMHz(_ hz: Double?) -> Double? {
            guard let hz, hz > 0 else { return nil }
            return hz / 1_000_000.0
        }

        func fmtMHz(_ mhz: Double) -> String {
            String(format: "%.5f", mhz)
        }

        func rangeTitle(prefix: String, low: Double?, high: Double?) -> String? {
            if let low, let high {
                if abs(high - low) < 0.001 { return "\(prefix) \(fmtMHz(low))" }
                return "\(prefix) \(fmtMHz(low))–\(fmtMHz(high))"
            }
            if let low { return "\(prefix) \(fmtMHz(low))" }
            if let high { return "\(prefix) \(fmtMHz(high))" }
            return nil
        }

        func parseCTCSSHz(_ text: String) -> Double? {
            ToneParser.parseCTCSSHz(text)
        }

        func qualityScore(_ t: SatNogTransmitter) -> Int {
            var score = 0
            if t.alive == true { score += 5 }
            if t.status?.lowercased() == "active" { score += 3 }
            if t.unconfirmed == false { score += 2 }
            if t.frequencyViolation == false { score += 1 }

            if let type = t.type?.lowercased() {
                if type.contains("transponder") { score += 2 }
                if type.contains("transceiver") { score += 1 }
            }

            let modeText = ((t.mode ?? "") + " " + (t.uplinkMode ?? "")).lowercased()
            if modeText.contains("fm") { score += 4 }
            if modeText.contains("afsk") || modeText.contains("gmsk") { score += 1 }
            if modeText.contains("cw") || modeText.contains("ssb") { score += 1 }

            let desc = (t.description ?? "").lowercased()
            if desc.contains("voice") || desc.contains("repeater") { score += 6 }
            if desc.contains("aprs") { score += 4 }
            if desc.contains("packet") { score += 2 }
            if desc.contains("telemetry") { score -= 1 }
            if desc.contains("beacon") { score -= 1 }

            if t.uplinkLow != nil { score += 2 }
            if t.downlinkLow != nil { score += 2 }
            return score
        }

        let sorted = transmitters.sorted {
            let a = qualityScore($0)
            let b = qualityScore($1)
            if a != b { return a > b }
            return ($0.description ?? "") < ($1.description ?? "")
        }

        var out: [SatFrequencyOption] = []
        out.reserveCapacity(sorted.count)

        var seenKeys = Set<String>()
        seenKeys.reserveCapacity(sorted.count)

        for t in sorted {
            let dlLow = hzToMHz(t.downlinkLow)
            let dlHigh = hzToMHz(t.downlinkHigh)
            let ulLow = hzToMHz(t.uplinkLow)
            let ulHigh = hzToMHz(t.uplinkHigh)

            // Pick a reasonable nominal frequency: center of range when available.
            let rxNom = (dlLow != nil && dlHigh != nil) ? ((dlLow! + dlHigh!) / 2.0) : (dlLow ?? dlHigh)
            var txNom = (ulLow != nil && ulHigh != nil) ? ((ulLow! + ulHigh!) / 2.0) : (ulLow ?? ulHigh)
            if rxNom == nil && txNom == nil { continue }

            // Band-limit to what the radio can actually tune.
            // Require a supported downlink (RX) to keep options relevant.
            if let rx = rxNom {
                if !isSupportedTuningMHz(rx) { continue }
            } else {
                continue
            }
            if let tx = txNom, !isSupportedTuningMHz(tx) {
                // Keep the option for RX-only monitoring; avoid pushing an out-of-range TX.
                txNom = nil
            }

            let descText = (t.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let tones: (rx: Double?, tx: Double?) = descText.isEmpty ? (rx: nil, tx: nil) : ToneParser.guessRxTxCTCSSHz(descText)
            let guessedRxTone: Double? = tones.rx
            let guessedTxTone: Double? = tones.tx

            // Intentionally quiet: tone parsing is best-effort.

            var parts: [String] = []
            if let type = t.type, !type.isEmpty { parts.append(type) }
            if let mode = t.mode, !mode.isEmpty { parts.append(mode) }
            if let uplinkMode = t.uplinkMode, !uplinkMode.isEmpty, uplinkMode != t.mode { parts.append("UL \(uplinkMode)") }

            var freqBits: [String] = []
            if let dl = rangeTitle(prefix: "DL", low: dlLow, high: dlHigh) { freqBits.append(dl) }
            if let ul = rangeTitle(prefix: "UL", low: ulLow, high: ulHigh) { freqBits.append(ul) }
            if let driftHz = t.downlinkDrift, driftHz != 0 {
                freqBits.append(String(format: "drift %+g Hz", driftHz))
            }

            let labelPrefix = parts.isEmpty ? "" : (parts.joined(separator: " ") + " ")
            let labelFreq = freqBits.isEmpty ? "" : ("(" + freqBits.joined(separator: ", ") + ")")
            let desc = descText.isEmpty ? nil : descText
            let title = [labelPrefix + (desc ?? "Transmitter"), labelFreq].joined(separator: labelFreq.isEmpty ? "" : " ")

            let key = String(format: "rx=%.5f|tx=%.5f|m=%@|um=%@|rt=%.1f|tt=%.1f", rxNom ?? -1, txNom ?? -1, (t.mode ?? ""), (t.uplinkMode ?? ""), guessedRxTone ?? -1, guessedTxTone ?? -1)
            if seenKeys.contains(key) { continue }
            seenKeys.insert(key)

            out.append(SatFrequencyOption(
                id: "tx-\(t.uuid)",
                title: title,
                rxMHz: rxNom,
                txMHz: txNom,
                rxCTCSSHz: guessedRxTone,
                txCTCSSHz: guessedTxTone,
                isCustom: false
            ))
        }

        // Deterministic ordering: prefer entries with both UL+DL.
        out.sort {
            let aScore = (($0.rxMHz != nil) ? 1 : 0) + (($0.txMHz != nil) ? 1 : 0)
            let bScore = (($1.rxMHz != nil) ? 1 : 0) + (($1.txMHz != nil) ? 1 : 0)
            if aScore != bScore { return aScore > bScore }
            return $0.title < $1.title
        }
        return out
    }

    private static func transmittersForFrequencyOptions(_ txs: [SatNogTransmitter], satNoradId: Int? = nil) -> [SatNogTransmitter] {
        let withFreq = txs.filter { $0.downlinkLow != nil || $0.uplinkLow != nil || $0.downlinkHigh != nil || $0.uplinkHigh != nil }

        // Prefer known-good entries, but fall back if SatNOGS marks things oddly.
        let strict = withFreq.filter { t in
            if t.alive == false { return false }
            if t.frequencyViolation == true { return false }
            if t.unconfirmed == true { return false }
            if let status = t.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !status.isEmpty {
                return status == "active"
            }
            return true
        }

        // ISS: keep the FM voice repeater even if SatNOGS flags it oddly.
        if satNoradId == 25544 {
            func nearHz(_ hz: Double?, _ target: Double, tol: Double) -> Bool {
                guard let hz else { return false }
                return abs(hz - target) <= tol
            }
            let voiceRepeater = withFreq.filter { t in
                let modeText = ((t.mode ?? "") + " " + (t.uplinkMode ?? "")).lowercased()
                guard modeText.contains("fm") else { return false }
                let rxOk = nearHz(t.downlinkLow ?? t.downlinkHigh, 437_800_000, tol: 10_000)
                let txOk = nearHz(t.uplinkLow ?? t.uplinkHigh, 145_990_000, tol: 10_000)
                return rxOk && txOk
            }
            if !voiceRepeater.isEmpty {
                var out = strict
                let strictIds = Set(strict.map(\.uuid))
                for t in voiceRepeater where !strictIds.contains(t.uuid) {
                    out.append(t)
                }
                if !out.isEmpty { return out }
            }
        }

        if !strict.isEmpty { return strict }
        return withFreq.filter { $0.alive != false }
    }

    private static func preferredDefaultFrequencyOptionId(for satId: Int, options: [SatFrequencyOption]) -> String? {
        // ISS: default to the FM voice repeater (UL 145.990 / DL 437.800, typically CTCSS 67.0 on uplink).
        guard satId == 25544 else { return nil }

        func near(_ a: Double?, _ b: Double, tol: Double) -> Bool {
            guard let a else { return false }
            return abs(a - b) <= tol
        }

        let targetRx = 437.800
        let targetTx = 145.990

        // First pass: exact-ish frequency match.
        if let best = options.first(where: { near($0.rxMHz, targetRx, tol: 0.010) && near($0.txMHz, targetTx, tol: 0.010) }) {
            return best.id
        }

        // Second pass: text match (handles variations if frequencies change slightly).
        let keywords = ["voice repeater", "fm - voice repeater", "repeater"]
        if let best = options.first(where: { opt in
            let t = opt.title.lowercased()
            return t.contains("fm") && keywords.contains(where: { t.contains($0) })
        }) {
            return best.id
        }

        return nil
    }

    private func selectedTonesFromFrequencyOption() -> (rx: Double?, tx: Double?) {
        guard let selected = frequencyOptions.first(where: { $0.id == selectedFrequencyOptionId }) else { return (nil, nil) }
        guard !selected.isCustom else { return (nil, nil) }
        return (selected.rxCTCSSHz, selected.txCTCSSHz)
    }

    private func fetchPassesForCurrentList(limit: Int) async {
        guard let obs = observerLocation else { return }
        let subset = Array(favoriteSatellites.prefix(limit))
        guard !subset.isEmpty else { return }

        // N2YO /radiopasses is 100/hr. Keep it bounded.
        do {
            for sat in subset {
                if Task.isCancelled { return }
                if passCache[sat.id] != nil { continue }
                let passes = try await n2yo.radioPasses(
                    satId: sat.id,
                    observerLat: obs.coordinate.latitude,
                    observerLng: obs.coordinate.longitude,
                    observerAltMeters: obs.altitude,
                    days: 1,
                    minElevationDeg: Int(minElevationDeg.rounded())
                )
                let mapped = Array(passes.passes.prefix(3)).map {
                    Pass(startUTC: $0.startUTC, maxEl: $0.maxEl, maxUTC: $0.maxUTC, endUTC: $0.endUTC)
                }
                if !mapped.isEmpty {
                    passCache[sat.id] = mapped
                    updatePassesInLists(satId: sat.id, passes: mapped)
                    rebuildNowSoonList()
                }
                // Space out requests a bit.
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        } catch {
            // Ignore; pass data is best-effort.
        }
    }

    private func fetchPassForSatellite(_ satId: Int) async {
        guard let obs = observerLocation else { return }
        guard passCache[satId] == nil else { return }

        beginPassFetch(clearStatus: true)
        defer { endPassFetch() }
        do {
            let passes = try await n2yo.radioPasses(
                satId: satId,
                observerLat: obs.coordinate.latitude,
                observerLng: obs.coordinate.longitude,
                observerAltMeters: obs.altitude,
                days: 1,
                minElevationDeg: Int(minElevationDeg.rounded())
            )
            let mapped = Array(passes.passes.prefix(3)).map {
                Pass(startUTC: $0.startUTC, maxEl: $0.maxEl, maxUTC: $0.maxUTC, endUTC: $0.endUTC)
            }
            if !mapped.isEmpty {
                passCache[satId] = mapped
                updatePassesInLists(satId: satId, passes: mapped)
                rebuildNowSoonList()
            }
        } catch {
            if Self.isCancellationLike(error) { return }
            if let e = error as? N2YOClientError, case .missingAPIKey = e {
                isMissingN2YOAPIKey = true
            }
            passStatusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func formatDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return "Today " + Self.timeFormatter.string(from: date)
        }
        if cal.isDateInTomorrow(date) {
            return "Tomorrow " + Self.timeFormatter.string(from: date)
        }
        return Self.dateTimeFormatter.string(from: date)
    }

    private func updatePassesInLists(satId: Int, passes: [Pass]) {
        if let idx = favoriteSatellites.firstIndex(where: { $0.id == satId }) {
            favoriteSatellites[idx].passes = passes
        }
        if let idx = discoverSatellites.firstIndex(where: { $0.id == satId }) {
            discoverSatellites[idx].passes = passes
        }
        if let idx = nowSoonSatellites.firstIndex(where: { $0.id == satId }) {
            nowSoonSatellites[idx].passes = passes
        }
        if let idx = lastAboveRows.firstIndex(where: { $0.id == satId }) {
            lastAboveRows[idx].passes = passes
        }
    }

    private func applyMinElevationFilterToDiscover() {
        let minEl = minElevationDeg
        let filtered = lastAboveRows.filter { row in
            guard let el = row.elevationDeg else { return true }
            let supported = supportedSatelliteCache[row.id] ?? false
            let favorite = favoriteSatelliteIds.contains(row.id)
            // Verified-only: show supported items; always show favorites.
            return el >= minEl && (supported || favorite)
        }
        discoverSatellites = filtered.sorted {
            let a = $0.elevationDeg ?? -90
            let b = $1.elevationDeg ?? -90
            if a != b { return a > b }
            return $0.name < $1.name
        }
    }

    private func rebuildNowSoonList() {
        let now = Date()
        let nowUnix = Int(now.timeIntervalSince1970)
        let soonWindowSec = 6 * 3600

        var combined: [SatelliteRow] = []
        var seen = Set<Int>()
        seen.reserveCapacity(discoverSatellites.count + favoriteSatellites.count)

        for s in discoverSatellites {
            combined.append(s)
            seen.insert(s.id)
        }

        for s in favoriteSatellites {
            if seen.contains(s.id) { continue }
            if let next = s.passes?.first, next.startUTC <= (nowUnix + soonWindowSec), next.endUTC >= nowUnix {
                combined.append(s)
                seen.insert(s.id)
            }
        }

        combined.sort {
            let aEl = $0.elevationDeg ?? -90
            let bEl = $1.elevationDeg ?? -90
            if aEl != bEl { return aEl > bEl }
            let aStart = $0.passes?.first?.startUTC ?? Int.max
            let bStart = $1.passes?.first?.startUTC ?? Int.max
            if aStart != bStart { return aStart < bStart }
            return $0.name < $1.name
        }

        nowSoonSatellites = combined
    }

    func trackingCountdownText(now: Date = Date()) -> String? {
        guard let satId = selectedSatelliteId else { return nil }
        guard let passes = passCache[satId] else { return nil }
        let nowUnix = Int(now.timeIntervalSince1970)

        if let active = passes.first(where: { $0.startUTC <= nowUnix && $0.endUTC >= nowUnix }) {
            return "In range now, ends in " + Self.formatDuration(seconds: active.endUTC - nowUnix)
        }
        if let next = passes.first(where: { $0.startUTC > nowUnix }) {
            return "In range in " + Self.formatDuration(seconds: next.startUTC - nowUnix)
        }
        return nil
    }

    private static func formatDuration(seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        if m > 0 { return String(format: "%dm %02ds", m, sec) }
        return String(format: "%ds", sec)
    }

    private static func estimateElevationDeg(observer: CLLocation, satLat: Double, satLng: Double, satAltitudeKm: Double) -> Double {
        // Simple spherical-Earth estimate (UI filtering only).
        let deg2rad = Double.pi / 180.0
        let latO = observer.coordinate.latitude * deg2rad
        let lonO = observer.coordinate.longitude * deg2rad
        let latS = satLat * deg2rad
        let lonS = satLng * deg2rad

        let earthRadiusM = 6_371_000.0
        let ro = earthRadiusM + max(0.0, observer.altitude)
        let rs = earthRadiusM + max(0.0, satAltitudeKm * 1_000.0)

        func ecef(r: Double, lat: Double, lon: Double) -> (x: Double, y: Double, z: Double) {
            let cl = cos(lat)
            return (x: r * cl * cos(lon), y: r * cl * sin(lon), z: r * sin(lat))
        }

        let o = ecef(r: ro, lat: latO, lon: lonO)
        let s = ecef(r: rs, lat: latS, lon: lonS)
        let v = (x: s.x - o.x, y: s.y - o.y, z: s.z - o.z)

        let vMag = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
        if vMag <= 0 { return -90 }
        let upMag = sqrt(o.x * o.x + o.y * o.y + o.z * o.z)
        if upMag <= 0 { return -90 }
        let up = (x: o.x / upMag, y: o.y / upMag, z: o.z / upMag)
        let dot = (v.x * up.x + v.y * up.y + v.z * up.z) / vMag
        let clamped = max(-1.0, min(1.0, dot))
        return asin(clamped) * 180.0 / Double.pi
    }
}

extension SatelliteTrackingViewModel: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        requestLocationIfNeeded()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        observerLocation = last

        // Make sure favorites populate even if /above is slow/fails.
        if favoriteSatellites.isEmpty {
            Task { await refreshFavorites() }
        }

        if favoriteSatellites.isEmpty && discoverSatellites.isEmpty {
            refreshAbove()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        if h.isFinite {
            deviceHeadingDeg = h
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Best-effort only; location errors can be transient.
    }
}
