import SwiftUI
import MapKit

struct SatelliteTrackingView: View {
    @EnvironmentObject private var radioManager: RadioManager
    @StateObject private var vm = SatelliteTrackingViewModel()

    @State private var mapCamera: MapCameraPosition = .automatic
    @State private var pendingRecenterSatId: Int?
    @State private var isMapExpanded: Bool = false

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
        var coords: [CLLocationCoordinate2D] = []
        coords.reserveCapacity(pathPositions.count)
        for p in pathPositions {
            coords.append(CLLocationCoordinate2D(latitude: p.latDeg, longitude: p.lonDeg))
        }
        return coords
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

    private var mapContent: some View {
        Map(position: $mapCamera, content: {
            UserAnnotation()

            if let coord = selectedCoordinate {
                let name = vm.selectedSatelliteName ?? "Satellite"
                Annotation(name, coordinate: coord) {
                    VStack(spacing: 2) {
                        Image(systemName: "dot.circle.fill")
                            .foregroundColor(.orange)
                        Text(name)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: 140)
                    }
                }

                if let radius = footprintRadiusMeters {
                    MapCircle(center: coord, radius: radius)
                        .foregroundStyle(.orange.opacity(0.08))
                        .stroke(.orange.opacity(0.25), lineWidth: 1)
                }
            }

            if pathPolylineNear.count >= 2 {
                MapPolyline(coordinates: pathPolylineNear)
                    .stroke(.orange.opacity(0.8), lineWidth: 3)
            }

            if pathPolylineFuture.count >= 2 {
                MapPolyline(coordinates: pathPolylineFuture)
                    .stroke(
                        .orange.opacity(0.35),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [8, 6])
                    )
            }

            if let last = pathLastCoordinate, pathPolylineFuture.count >= 2 {
                Annotation("Future", coordinate: last) {
                    Circle()
                        .fill(.orange.opacity(0.35))
                        .frame(width: 8, height: 8)
                }
            }
        })
    }

    private var mapCard: some View {
        ZStack {
            mapContent
                .allowsHitTesting(false)

            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { isMapExpanded = true }
        }
    }

    private var footprintRadiusMeters: CLLocationDistance? {
        guard let altKm = vm.selectedAltitudeKm else { return nil }
        // Radio horizon approximation on spherical Earth.
        // d = sqrt((R+h)^2 - R^2)
        let R = 6_371_000.0
        let h = max(0.0, altKm) * 1_000.0
        let d = sqrt((R + h) * (R + h) - R * R)
        if d.isFinite, d > 0 { return d }
        return nil
    }

    var body: some View {
        List {
            Section {
                if !vm.isLocationAuthorized {
                    Text("Location is required to compute passes and pointing.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let msg = vm.passStatusMessage, !msg.isEmpty {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if vm.isLoadingPasses {
                    ProgressView("Loading passes...")
                        .font(.caption)
                }

                mapCard
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                trackingControls
            } header: {
                header
            }

            Section {
                if vm.favoriteSatellites.isEmpty {
                    Text("Tap Add favorites or swipe a satellite in Discover to favorite it.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                NavigationLink {
                    SatelliteSearchView(vm: vm)
                } label: {
                    Label("Add favorites", systemImage: "star.badge.plus")
                }

                ForEach(vm.favoriteSatellites) { sat in
                    Button {
                        vm.selectSatellite(sat.id, name: sat.name)
                        vm.startTrackingSelected()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sat.name)
                                    .font(.headline)
                                Text(vm.passText(for: sat))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if vm.selectedSatelliteId == sat.id {
                                Image(systemName: vm.isTracking ? "dot.radiowaves.left.and.right" : "checkmark.circle.fill")
                                    .foregroundColor(vm.isTracking ? .orange : .secondary)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if sat.id != 25544 {
                            Button(role: .destructive) {
                                vm.removeFavorite(sat.id)
                            } label: {
                                Text("Remove")
                            }
                        }
                    }
                }
            } header: {
                Text("Favorites")
            }

            Section {
                if vm.nowSoonSatellites.isEmpty {
                    Text("No passes coming up soon.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                ForEach(vm.nowSoonSatellites.prefix(15)) { sat in
                    Button {
                        vm.selectSatellite(sat.id, name: sat.name)
                        vm.startTrackingSelected()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sat.name)
                                    .font(.subheadline)
                                Text(vm.passText(for: sat))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: vm.favoriteSatelliteIds.contains(sat.id) ? "star.fill" : "star")
                                .foregroundColor(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if vm.favoriteSatelliteIds.contains(sat.id) {
                            if sat.id != 25544 {
                                Button(role: .destructive) {
                                    vm.removeFavorite(sat.id)
                                } label: {
                                    Text("Remove")
                                }
                            }
                        } else {
                            Button {
                                vm.addFavorite(sat.id, name: sat.name)
                            } label: {
                                Text("Add")
                            }
                            .tint(.orange)
                        }
                    }
                }
            } header: {
                Text("Now & soon")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Min elevation")
                            .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.0f deg", vm.minElevationDeg))
                                .font(.caption)
                                .foregroundColor(.secondary)
                    }
                    Slider(value: $vm.minElevationDeg, in: 0...30, step: 1)
                }

                if vm.discoverSatellites.isEmpty {
                    Text("No satellites above horizon (try lowering min elevation).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(vm.discoverSatellites) { sat in
                        Button {
                            vm.selectSatellite(sat.id, name: sat.name)
                            vm.startTrackingSelected()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sat.name)
                                        .font(.subheadline)
                                    Text("NORAD \(sat.id)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if vm.favoriteSatelliteIds.contains(sat.id) {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.secondary)
                                } else {
                                    Image(systemName: "star")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if vm.favoriteSatelliteIds.contains(sat.id) {
                                if sat.id != 25544 {
                                    Button(role: .destructive) {
                                        vm.removeFavorite(sat.id)
                                    } label: {
                                        Text("Remove")
                                    }
                                }
                            } else {
                                Button {
                                    vm.addFavorite(sat.id, name: sat.name)
                                } label: {
                                    Text("Add")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }
            } header: {
                Text("Discover (above horizon)")
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isMapExpanded) {
            NavigationStack {
                mapContent
                    .mapControls {
                        MapUserLocationButton()
                        MapCompass()
                        MapScaleView()
                        MapPitchToggle()
                    }
                    .navigationTitle(vm.selectedSatelliteName ?? "Map")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { isMapExpanded = false }
                        }
                    }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh") { vm.refreshAbove() }
                    .disabled(vm.observerLocation == nil)
            }
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
                let region = MKCoordinateRegion(center: coord, span: span)
                mapCamera = .region(region)
                pendingRecenterSatId = nil
            }
        }
        .onChange(of: vm.dopplerRxMHz) {
            vm.onDopplerUpdated(radioManager: radioManager)
        }
        .onChange(of: vm.selectedSatelliteId) {
            pendingRecenterSatId = vm.selectedSatelliteId
            vm.onSelectionChanged(radioManager: radioManager)
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
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 24)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Amateur Satellite")
                    .font(.headline)

                if let el = vm.selectedElevation, let az = vm.selectedAzimuth {
                    let rangeText = vm.selectedRangeKm.map { String(format: "  R %.0f km", $0) } ?? ""
                    let shiftText = vm.dopplerRxShiftHz.map { String(format: "  Doppler %+d Hz", $0) } ?? ""
                    Text(String(format: "Az %.0f deg  El %.0f deg%@%@", az, el, rangeText, shiftText))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let countdown = vm.trackingCountdownText() {
                        Text(countdown)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Intentionally omit tracking source (offline/online).
                } else {
                    Text("Tap a satellite to track")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
    }

    private var trackingControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(vm.selectedSatelliteName ?? "Select a satellite")
                .font(.headline)

            if let detail = vm.selectedSatelliteDetailText, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Keep noisy network/metadata errors out of the UI; tracking is best-effort.

            if vm.isLoading {
                ProgressView("Loading satellites...")
            }

            if vm.isTracking {
                Button(role: .destructive) {
                    vm.stopTracking()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill")
                            .foregroundStyle(.white)
                        Text("Stop tracking")
                            .foregroundStyle(.white)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }

            Picker("Frequency", selection: $vm.selectedFrequencyOptionId) {
                ForEach(vm.frequencyOptions) { p in
                    Text(p.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .tag(p.id)
                }
            }
            .pickerStyle(.menu)
            .disabled(vm.selectedSatelliteId == nil)

            if vm.isLoadingFrequencies {
                ProgressView("Loading frequencies...")
                    .font(.caption)
            }

            if vm.selectedFrequencyOptionId == "custom" {
                HStack {
                    Text("RX")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("145.800", value: $vm.nominalRxMHz, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)

                    Spacer()

                    Text("TX")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("145.800", value: $vm.nominalTxMHz, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
            } else {
                HStack {
                    Text(String(format: "RX %.3f MHz  TX %.3f MHz", vm.nominalRxMHz, vm.nominalTxMHz))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 12)
    }
}
