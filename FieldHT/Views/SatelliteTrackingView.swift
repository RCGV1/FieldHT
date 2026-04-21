import SwiftUI
import MapKit

struct SatelliteTrackingView: View {
    @EnvironmentObject private var radioManager: RadioManager
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var vm = SatelliteTrackingViewModel()

    @State private var mapCamera: MapCameraPosition = .automatic
    @State private var pendingRecenterSatId: Int?
    @State private var isMapExpanded = false
    @State private var showingSearch = false
    @State private var showingFrequencyPlans = false
    @State private var libraryShelf: LibraryShelf = .ready

    private enum LibraryShelf: String, CaseIterable, Identifiable {
        case ready
        case favorites
        case visible

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ready: return "Ready"
            case .favorites: return "Favorites"
            case .visible: return "Visible"
            }
        }

        var emptyTitle: String {
            switch self {
            case .ready: return "No good passes queued"
            case .favorites: return "No favorites yet"
            case .visible: return "Nothing above your cutoff"
            }
        }

        var emptyMessage: String {
            switch self {
            case .ready:
                return "When a pass is coming up or already overhead, it will show up here for one-tap tracking."
            case .favorites:
                return "Save the satellites you care about so they stay close at hand."
            case .visible:
                return "Try lowering the elevation filter or refreshing once your location is locked in."
            }
        }
    }

    private enum StatusStyle {
        case idle
        case upcoming
        case live

        var symbol: String {
            switch self {
            case .idle: return "sparkles"
            case .upcoming: return "clock.badge"
            case .live: return "dot.radiowaves.left.and.right"
            }
        }

        var tint: Color {
            switch self {
            case .idle: return Color(red: 0.31, green: 0.72, blue: 0.92)
            case .upcoming: return Color(red: 0.96, green: 0.68, blue: 0.20)
            case .live: return Color(red: 0.38, green: 0.95, blue: 0.63)
            }
        }
    }

    private var selectedCoordinate: CLLocationCoordinate2D? {
        guard let first = vm.selectedPositions.first else { return nil }
        return CLLocationCoordinate2D(latitude: first.latDeg, longitude: first.lonDeg)
    }

    private var pathPositions: [OfflineSatPosition] {
        if vm.selectedPathPositions.count >= 2 {
            return vm.selectedPathPositions
        }
        return vm.selectedPositions
    }

    private var pathCoordinates: [CLLocationCoordinate2D] {
        pathPositions.map { CLLocationCoordinate2D(latitude: $0.latDeg, longitude: $0.lonDeg) }
    }

    private var pathPolylineNear: [CLLocationCoordinate2D] {
        let coords = pathCoordinates
        guard coords.count >= 2 else { return [] }
        let splitIndex = max(2, min(coords.count - 1, coords.count / 4))
        return Array(coords.prefix(splitIndex))
    }

    private var pathPolylineFuture: [CLLocationCoordinate2D] {
        let coords = pathCoordinates
        guard coords.count >= 2 else { return [] }
        let splitIndex = max(2, min(coords.count - 1, coords.count / 4))
        return Array(coords[(splitIndex - 1)...])
    }

    private var pathLastCoordinate: CLLocationCoordinate2D? {
        pathCoordinates.last
    }

    private var selectedSatelliteRow: SatelliteTrackingViewModel.SatelliteRow? {
        guard let satId = vm.selectedSatelliteId else { return nil }
        let pools = [
            vm.favoriteSatellites,
            vm.nowSoonSatellites,
            vm.discoverSatellites
        ]

        for pool in pools {
            if let row = pool.first(where: { $0.id == satId }) {
                return row
            }
        }

        return nil
    }

    private var featuredSatellite: SatelliteTrackingViewModel.SatelliteRow? {
        vm.nowSoonSatellites.first ?? vm.favoriteSatellites.first ?? vm.discoverSatellites.first
    }

    private var selectedPass: SatelliteTrackingViewModel.Pass? {
        selectedSatelliteRow?.passes?.first
    }

    private var visibleRows: [SatelliteTrackingViewModel.SatelliteRow] {
        switch libraryShelf {
        case .ready:
            return Array(vm.nowSoonSatellites.prefix(10))
        case .favorites:
            return vm.favoriteSatellites
        case .visible:
            return Array(vm.discoverSatellites.prefix(16))
        }
    }

    private var countsSummary: [(title: String, value: Int)] {
        [
            ("Ready", vm.nowSoonSatellites.count),
            ("Favorites", vm.favoriteSatellites.count),
            ("Visible", vm.discoverSatellites.count)
        ]
    }

    private var missionStatus: (title: String, subtitle: String, style: StatusStyle) {
        guard vm.selectedSatelliteId != nil else {
            return ("Pick a satellite", "Start with a pass that is live now or browse the catalog.", .idle)
        }

        if vm.isTracking, let countdown = vm.trackingCountdownText(), let el = vm.selectedElevation, el > 0 {
            return ("Live track", countdown, .live)
        }

        if let countdown = vm.trackingCountdownText() {
            return ("Next pass queued", countdown, .upcoming)
        }

        return ("Satellite selected", "Choose a frequency plan and start tracking when you are ready.", .idle)
    }

    private var heroMapHeight: CGFloat {
        vm.selectedSatelliteId == nil ? 150 : 210
    }

    private var footprintRadiusMeters: CLLocationDistance? {
        guard let altKm = vm.selectedAltitudeKm else { return nil }
        let earthRadius = 6_371_000.0
        let altitude = max(0.0, altKm) * 1_000.0
        let radius = sqrt((earthRadius + altitude) * (earthRadius + altitude) - earthRadius * earthRadius)
        return radius.isFinite && radius > 0 ? radius : nil
    }

    private var backgroundGradient: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.05, blue: 0.11),
                    Color(red: 0.05, green: 0.10, blue: 0.18),
                    Color(red: 0.02, green: 0.03, blue: 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.95, green: 0.53, blue: 0.18).opacity(0.16),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 320
            )

            RadialGradient(
                colors: [
                    Color(red: 0.24, green: 0.67, blue: 0.95).opacity(0.22),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 40,
                endRadius: 420
            )
        }
    }

    private var panelStroke: Color {
        .white.opacity(colorScheme == .dark ? 0.12 : 0.18)
    }

    private var primaryText: Color {
        .white.opacity(0.96)
    }

    private var secondaryText: Color {
        .white.opacity(0.68)
    }

    private var accentOrange: Color {
        Color(red: 0.96, green: 0.62, blue: 0.21)
    }

    private var accentCyan: Color {
        Color(red: 0.32, green: 0.78, blue: 0.97)
    }

    private var mapContent: some View {
        Map(position: $mapCamera) {
            UserAnnotation()

            if let coord = selectedCoordinate {
                Annotation(vm.selectedSatelliteName ?? "Satellite", coordinate: coord) {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(accentOrange)
                            .frame(width: 12, height: 12)
                            .overlay {
                                Circle()
                                    .stroke(accentOrange.opacity(0.35), lineWidth: 10)
                            }

                        Text(vm.selectedSatelliteName ?? "Satellite")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.35), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }

                if let radius = footprintRadiusMeters {
                    MapCircle(center: coord, radius: radius)
                        .foregroundStyle(accentOrange.opacity(0.08))
                        .stroke(accentOrange.opacity(0.28), lineWidth: 1.5)
                }
            }

            if pathPolylineNear.count >= 2 {
                MapPolyline(coordinates: pathPolylineNear)
                    .stroke(accentOrange, lineWidth: 3)
            }

            if pathPolylineFuture.count >= 2 {
                MapPolyline(coordinates: pathPolylineFuture)
                    .stroke(
                        accentCyan.opacity(0.65),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [10, 8])
                    )
            }

            if let last = pathLastCoordinate, pathPolylineFuture.count >= 2 {
                Annotation("Future", coordinate: last) {
                    Circle()
                        .fill(accentCyan)
                        .frame(width: 9, height: 9)
                }
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                trackingDeck
                orbitPanel

                if vm.selectedSatelliteId != nil {
                    radioPlanPanel
                }

                missionBrowserPanel
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 34)
        }
        .background(backgroundGradient.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .navigationTitle("Satellite")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .tint(primaryText)
            }
        }
        .sheet(isPresented: $showingSearch) {
            NavigationStack {
                SatelliteSearchView(vm: vm)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isMapExpanded) {
            NavigationStack {
                mapContent
                    .mapControls {
                        MapUserLocationButton()
                        MapCompass()
                        MapScaleView()
                        MapPitchToggle()
                    }
                    .navigationTitle(vm.selectedSatelliteName ?? "Orbit")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { isMapExpanded = false }
                        }
                    }
            }
        }
        .refreshable {
            vm.refreshAbove()
        }
        .onAppear {
            vm.requestLocationIfNeeded()
        }
        .onDisappear {
            vm.stop()
        }
        .onChange(of: vm.selectedPositions) {
            if let satId = vm.selectedSatelliteId,
               pendingRecenterSatId == satId,
               let coord = selectedCoordinate {
                let span = MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 30)
                mapCamera = .region(MKCoordinateRegion(center: coord, span: span))
                pendingRecenterSatId = nil
            }
        }
        .onChange(of: vm.selectedSatelliteId) {
            pendingRecenterSatId = vm.selectedSatelliteId
            vm.onSelectionChanged(radioManager: radioManager)
        }
        .onChange(of: vm.dopplerRxMHz) {
            vm.onDopplerUpdated(radioManager: radioManager)
        }
        .onChange(of: vm.selectedFrequencyOptionId) {
            vm.onFrequencyOptionChanged(radioManager: radioManager)
        }
        .onChange(of: vm.nominalRxMHz) {
            vm.scheduleFreqModeParameterSync(radioManager: radioManager)
        }
        .onChange(of: vm.nominalTxMHz) {
            vm.scheduleFreqModeParameterSync(radioManager: radioManager)
        }
        .sensoryFeedback(.selection, trigger: vm.selectedSatelliteId)
        .sensoryFeedback(.success, trigger: vm.isTracking)
    }

    private var trackingDeck: some View {
        SatellitePanel(
            title: vm.selectedSatelliteName ?? "Mission Control",
            subtitle: vm.selectedSatelliteName == nil
                ? "Follow active amateur satellites, preview their path, and push a clean radio plan without digging through several lists."
                : selectedSubtitleText,
            accessory: {
                if vm.selectedSatelliteId != nil {
                    statusBadge(
                        title: missionStatus.title,
                        symbol: missionStatus.style.symbol,
                        tint: missionStatus.style.tint
                    )
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 18) {
                if vm.selectedSatelliteId == nil {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(missionStatus.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(secondaryText)

                        if let featuredRecommendationText {
                            infoStrip(
                                title: featuredRecommendationText.title,
                                detail: featuredRecommendationText.detail,
                                symbol: "scope",
                                tint: accentOrange
                            )
                        }

                        ViewThatFits {
                            HStack(spacing: 10) {
                                Button {
                                    if let featuredSatellite {
                                        selectAndTrack(featuredSatellite)
                                    }
                                } label: {
                                    Label("Track Best Pass", systemImage: "dot.radiowaves.left.and.right")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(accentOrange)
                                .disabled(featuredSatellite == nil)

                                Button {
                                    showingSearch = true
                                } label: {
                                    Label("Browse Catalog", systemImage: "magnifyingglass")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(.white.opacity(0.9))
                            }

                            VStack(spacing: 10) {
                                Button {
                                    if let featuredSatellite {
                                        selectAndTrack(featuredSatellite)
                                    }
                                } label: {
                                    Label("Track Best Pass", systemImage: "dot.radiowaves.left.and.right")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(accentOrange)
                                .disabled(featuredSatellite == nil)

                                Button {
                                    showingSearch = true
                                } label: {
                                    Label("Browse Catalog", systemImage: "magnifyingglass")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(.white.opacity(0.9))
                            }
                        }
                    }
                } else {
                    metricsGrid

                    if let passCardText = selectedPassCardText {
                        infoStrip(
                            title: passCardText.title,
                            detail: passCardText.detail,
                            symbol: passCardText.symbol,
                            tint: passCardText.tint
                        )
                    }

                    if let banner = statusBannerText {
                        infoStrip(
                            title: banner.title,
                            detail: banner.detail,
                            symbol: banner.symbol,
                            tint: banner.tint
                        )
                    }

                    Button {
                        if vm.isTracking {
                            vm.stopTracking()
                        } else {
                            vm.startTrackingSelected()
                        }
                    } label: {
                        Label(
                            vm.isTracking ? "Stop Tracking" : "Start Tracking",
                            systemImage: vm.isTracking ? "stop.fill" : "play.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(vm.isTracking ? .red.opacity(0.92) : accentOrange)
                }
            }
        }
    }

    private var orbitPanel: some View {
        SatellitePanel(
            title: "Orbit View",
            subtitle: vm.selectedSatelliteId == nil
                ? "Once you pick a satellite, this becomes your quick map and footprint preview."
                : "Your current position, the live target, and the short-term path all in one glance.",
            accessory: {
                Button {
                    isMapExpanded = true
                } label: {
                    Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(vm.selectedSatelliteId == nil)
                .opacity(vm.selectedSatelliteId == nil ? 0.45 : 1)
            }
        ) {
            if vm.selectedSatelliteId == nil {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.white.opacity(0.05))

                    VStack(spacing: 10) {
                        Image(systemName: "globe.americas.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(accentCyan)
                        Text("Select a satellite to preview its orbit path.")
                            .font(.subheadline)
                            .foregroundStyle(secondaryText)
                    }
                }
                .frame(height: heroMapHeight)
            } else {
                ZStack(alignment: .topLeading) {
                    mapContent
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .frame(height: heroMapHeight)

                    Text("Tap for full map")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(primaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.35), in: Capsule())
                        .padding(12)
                }
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .onTapGesture {
                    isMapExpanded = true
                }
            }
        }
    }

    private var radioPlanPanel: some View {
        SatellitePanel(
            title: "Radio Plan",
            subtitle: "Keep one clean frequency plan in view while the Doppler engine updates the live values."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    showingFrequencyPlans = true
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Active plan")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(secondaryText)

                            Text(selectedFrequencyPlanTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(primaryText)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)

                        if vm.isLoadingFrequencies {
                            ProgressView()
                                .tint(accentOrange)
                        } else {
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(secondaryText)
                                .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingFrequencyPlans) {
                    NavigationStack {
                        List {
                            ForEach(vm.selectableFrequencyOptions) { option in
                                Button {
                                    vm.selectedFrequencyOptionId = option.id
                                    showingFrequencyPlans = false
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(option.title)
                                                .foregroundStyle(.primary)
                                            if let rx = option.rxMHz, let tx = option.txMHz {
                                                Text(String(format: "RX %.5f  TX %.5f", rx, tx))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            } else if let rx = option.rxMHz {
                                                Text(String(format: "RX %.5f", rx))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            } else if let tx = option.txMHz {
                                                Text(String(format: "TX %.5f", tx))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if vm.selectedFrequencyOptionId == option.id {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(accentOrange)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .navigationTitle("Frequency Plans")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    showingFrequencyPlans = false
                                }
                            }
                        }
                    }
                }

                ViewThatFits {
                    HStack(spacing: 12) {
                        frequencyMetric(title: "RX", nominal: vm.nominalRxMHz, live: vm.dopplerRxMHz, tint: accentCyan)
                        frequencyMetric(title: "TX", nominal: vm.nominalTxMHz, live: vm.dopplerTxMHz, tint: accentOrange)
                    }

                    VStack(spacing: 12) {
                        frequencyMetric(title: "RX", nominal: vm.nominalRxMHz, live: vm.dopplerRxMHz, tint: accentCyan)
                        frequencyMetric(title: "TX", nominal: vm.nominalTxMHz, live: vm.dopplerTxMHz, tint: accentOrange)
                    }
                }

                if vm.selectedFrequencyOptionId == "custom" {
                    ViewThatFits {
                        HStack(spacing: 12) {
                            customFrequencyField(title: "RX", value: $vm.nominalRxMHz)
                            customFrequencyField(title: "TX", value: $vm.nominalTxMHz)
                        }

                        VStack(spacing: 12) {
                            customFrequencyField(title: "RX", value: $vm.nominalRxMHz)
                            customFrequencyField(title: "TX", value: $vm.nominalTxMHz)
                        }
                    }
                }

                if let message = vm.frequencyErrorMessage, !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(secondaryText)
                }

                if vm.hasMoreFrequencyOptions {
                    Button {
                        withAnimation(.snappy(duration: 0.28)) {
                            vm.showAllFrequencyOptions.toggle()
                        }
                    } label: {
                        Label(
                            vm.showAllFrequencyOptions ? "Show fewer plans" : "Show more plans",
                            systemImage: vm.showAllFrequencyOptions ? "chevron.up" : "chevron.down"
                        )
                        .font(.footnote.weight(.semibold))
                    }
                    .tint(primaryText)
                }
            }
        }
    }

    private var missionBrowserPanel: some View {
        SatellitePanel(
            title: "Mission Queue",
            subtitle: "Jump between the satellites that are ready now, the ones you care about, and everything currently above your horizon."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    ForEach(countsSummary, id: \.title) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(secondaryText)
                            Text("\(item.value)")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(primaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }

                Picker("Satellite shelf", selection: $libraryShelf) {
                    ForEach(LibraryShelf.allCases) { shelf in
                        Text(shelf.title).tag(shelf)
                    }
                }
                .pickerStyle(.segmented)

                if libraryShelf == .visible {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Minimum elevation")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(secondaryText)
                            Spacer()
                            Text("\(Int(vm.minElevationDeg.rounded()))°")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(primaryText)
                        }

                        Slider(value: $vm.minElevationDeg, in: 0...30, step: 1)
                            .tint(accentOrange)
                    }
                    .padding(14)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                if vm.isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(accentOrange)
                        Text("Refreshing visible passes…")
                            .font(.footnote)
                            .foregroundStyle(secondaryText)
                    }
                }

                if visibleRows.isEmpty {
                    emptyShelfView(for: libraryShelf)
                } else {
                    VStack(spacing: 10) {
                        ForEach(visibleRows) { sat in
                            satelliteRow(for: sat)
                        }
                    }
                }
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            metricTile(
                title: "Azimuth",
                value: vm.selectedAzimuth.map { String(format: "%.0f°", $0) } ?? "—",
                detail: "Bearing"
            )
            metricTile(
                title: "Elevation",
                value: vm.selectedElevation.map { String(format: "%.0f°", $0) } ?? "—",
                detail: "Look angle"
            )
            metricTile(
                title: "Range",
                value: vm.selectedRangeKm.map { String(format: "%.0f km", $0) } ?? "—",
                detail: "Slant distance"
            )
            metricTile(
                title: "Doppler",
                value: vm.dopplerRxShiftHz.map { String(format: "%+d Hz", $0) } ?? "—",
                detail: "RX shift"
            )
        }
    }

    private var selectedSubtitleText: String {
        let detail = vm.selectedSatelliteDetailText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let detail, !detail.isEmpty {
            return detail
        }
        return missionStatus.subtitle
    }

    private var featuredRecommendationText: (title: String, detail: String)? {
        guard let featuredSatellite else { return nil }
        return ("Best next target", "\(featuredSatellite.name) • \(shortSummary(for: featuredSatellite))")
    }

    private var selectedFrequencyPlanTitle: String {
        vm.frequencyOptions.first(where: { $0.id == vm.selectedFrequencyOptionId })?.title ?? "Custom"
    }

    private var selectedPassCardText: (title: String, detail: String, symbol: String, tint: Color)? {
        guard let pass = selectedPass else { return nil }

        let nowUnix = Int(Date().timeIntervalSince1970)
        let maxEl = Int(pass.maxEl.rounded())
        let durationMinutes = max(1, (pass.endUTC - pass.startUTC) / 60)
        let maxText = timeText(pass.maxUTC)

        if pass.startUTC <= nowUnix && pass.endUTC >= nowUnix {
            return (
                title: "In range now",
                detail: "Peaks at \(maxText) • max \(maxEl)° • about \(durationMinutes) min total",
                symbol: "dot.radiowaves.left.and.right",
                tint: Color(red: 0.38, green: 0.95, blue: 0.63)
            )
        }

        return (
            title: "Next pass",
            detail: "\(dateTimeText(pass.startUTC)) • max \(maxEl)° • around \(durationMinutes) min",
            symbol: "clock.arrow.circlepath",
            tint: accentOrange
        )
    }

    private var statusBannerText: (title: String, detail: String, symbol: String, tint: Color)? {
        if !vm.isLocationAuthorized {
            return (
                title: "Location needed",
                detail: "Pass timing and azimuth need your current position before the queue becomes useful.",
                symbol: "location.slash",
                tint: Color(red: 0.97, green: 0.59, blue: 0.28)
            )
        }

        if let msg = vm.passStatusMessage, !msg.isEmpty {
            return (
                title: "Pass status",
                detail: msg,
                symbol: "info.circle",
                tint: accentCyan
            )
        }

        if vm.isLoadingPasses {
            return (
                title: "Computing passes",
                detail: "Building the next useful windows from your current location.",
                symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                tint: accentCyan
            )
        }

        return nil
    }

    @ViewBuilder
    private func emptyShelfView(for shelf: LibraryShelf) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(shelf.emptyTitle)
                .font(.headline)
                .foregroundStyle(primaryText)
            Text(shelf.emptyMessage)
                .font(.subheadline)
                .foregroundStyle(secondaryText)

            HStack(spacing: 10) {
                Button {
                    if shelf == .favorites {
                        showingSearch = true
                    } else {
                        vm.refreshAbove()
                    }
                } label: {
                    Label(
                        shelf == .favorites ? "Browse satellites" : "Refresh queue",
                        systemImage: shelf == .favorites ? "magnifyingglass" : "arrow.clockwise"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(accentOrange)

                if shelf != .favorites {
                    Button("Browse") {
                        showingSearch = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.9))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func selectAndTrack(_ sat: SatelliteTrackingViewModel.SatelliteRow) {
        vm.selectSatellite(sat.id, name: sat.name)
        vm.startTrackingSelected()
    }

    private func satelliteRow(for sat: SatelliteTrackingViewModel.SatelliteRow) -> some View {
        HStack(spacing: 12) {
            Button {
                selectAndTrack(sat)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(sat.name)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(primaryText)
                                .lineLimit(1)

                            if vm.selectedSatelliteId == sat.id {
                                Image(systemName: vm.isTracking ? "dot.radiowaves.left.and.right" : "checkmark.circle.fill")
                                    .foregroundStyle(vm.isTracking ? accentOrange : accentCyan)
                            }
                        }

                        Text(shortSummary(for: sat))
                            .font(.subheadline)
                            .foregroundStyle(secondaryText)
                            .multilineTextAlignment(.leading)

                        Text("NORAD \(sat.id)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.46))
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            favoriteToggle(for: sat)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(vm.selectedSatelliteId == sat.id ? accentOrange.opacity(0.18) : .white.opacity(0.05))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(vm.selectedSatelliteId == sat.id ? accentOrange.opacity(0.42) : panelStroke, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func favoriteToggle(for sat: SatelliteTrackingViewModel.SatelliteRow) -> some View {
        let isFavorite = vm.favoriteSatelliteIds.contains(sat.id)

        Button {
            if isFavorite {
                vm.removeFavorite(sat.id)
            } else {
                vm.addFavorite(sat.id, name: sat.name)
            }
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.headline.weight(.semibold))
                .foregroundStyle(isFavorite ? accentOrange : secondaryText)
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.07), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isFavorite && sat.id == 25544)
        .opacity(isFavorite && sat.id == 25544 ? 0.75 : 1)
    }

    private func shortSummary(for sat: SatelliteTrackingViewModel.SatelliteRow) -> String {
        let nowUnix = Int(Date().timeIntervalSince1970)

        if let pass = sat.passes?.first {
            if pass.startUTC <= nowUnix && pass.endUTC >= nowUnix {
                return "In range now • max \(Int(pass.maxEl.rounded()))° • ends \(timeText(pass.endUTC))"
            }

            return "\(timeText(pass.startUTC)) • max \(Int(pass.maxEl.rounded()))°"
        }

        if let elevation = sat.elevationDeg {
            return String(format: "Visible now • elevation %.0f°", elevation)
        }

        return "Tap to inspect frequencies and start tracking."
    }

    private func timeText(_ unix: Int) -> String {
        SatelliteTrackingView.timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(unix)))
    }

    private func dateTimeText(_ unix: Int) -> String {
        SatelliteTrackingView.dateTimeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(unix)))
    }

    private func statusBadge(title: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white.opacity(0.96))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.24), in: Capsule())
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.55), lineWidth: 1)
        }
    }

    private func infoStrip(title: String, detail: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryText)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func metricTile(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.52))
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(primaryText)
                .contentTransition(.numericText())
            Text(detail)
                .font(.caption)
                .foregroundStyle(secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func frequencyMetric(title: String, nominal: Double, live: Double?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
            }

            Text(String(format: "%.3f", live ?? nominal))
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(primaryText)
                .contentTransition(.numericText())

            Text(String(format: "Base %.3f MHz", nominal))
                .font(.caption)
                .foregroundStyle(secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        }
    }

    private func customFrequencyField(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryText)

            TextField(title, value: value, format: .number.precision(.fractionLength(3)))
                .keyboardType(.decimalPad)
                .textFieldStyle(.plain)
                .font(.headline.monospacedDigit())
                .foregroundStyle(primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct SatellitePanel<Accessory: View, Content: View>: View {
    let title: String
    let subtitle: String?
    let accessory: Accessory
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    titleBlock
                    Spacer(minLength: 0)
                    accessory
                }

                VStack(alignment: .leading, spacing: 12) {
                    titleBlock
                    accessory
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            content
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.white.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white.opacity(0.96))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private extension SatellitePanel where Accessory == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, subtitle: subtitle, accessory: { EmptyView() }, content: content)
    }
}
