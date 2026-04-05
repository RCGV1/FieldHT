import SwiftUI

struct SatelliteSearchView: View {
    @ObservedObject var vm: SatelliteTrackingViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    private var trimmed: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var quickPicks: [SatelliteTrackingViewModel.SatelliteRow] {
        var seen = Set<Int>()
        var rows: [SatelliteTrackingViewModel.SatelliteRow] = []

        for sat in vm.nowSoonSatellites.prefix(6) where seen.insert(sat.id).inserted {
            rows.append(sat)
        }

        for sat in vm.favoriteSatellites.prefix(8) where seen.insert(sat.id).inserted {
            rows.append(sat)
        }

        return rows
    }

    private var suggestions: [SatelliteTrackingViewModel.SatelliteRow] {
        Array(quickPicks.prefix(6))
    }

    var body: some View {
        List {
            if trimmed.isEmpty {
                Section {
                    if quickPicks.isEmpty {
                        ContentUnavailableView(
                            "Start Searching",
                            systemImage: "magnifyingglass",
                            description: Text("Search by satellite name or NORAD number, or pick from the next useful passes once they load.")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(quickPicks) { sat in
                            browserRow(for: sat, detail: quickPickDetail(for: sat))
                        }
                    }
                } header: {
                    Text("Quick Picks")
                } footer: {
                    Text("Tap a satellite to load it into the tracking deck. Use the star to save or remove favorites.")
                }
            } else {
                Section {
                    if vm.isSearching {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Searching catalog…")
                                .foregroundStyle(.secondary)
                        }
                    } else if vm.searchResults.isEmpty {
                        ContentUnavailableView(
                            "No Matches",
                            systemImage: "satellite.dish",
                            description: Text("Try a different callsign, common name, or NORAD number.")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(vm.searchResults) { sat in
                            browserRow(for: sat, detail: resultDetail(for: sat))
                        }
                    }
                } header: {
                    Text("Results")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Browse Satellites")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Satellite name or NORAD"
        )
        .searchSuggestions {
            ForEach(suggestions) { sat in
                Button {
                    searchText = sat.name
                } label: {
                    Text(sat.name)
                }
                .searchCompletion(sat.name)
            }
        }
        .onChange(of: searchText) {
            vm.updateSearch(searchText)
        }
        .onAppear {
            vm.warmSatelliteSearchIndex()
            searchText = ""
            vm.updateSearch("")
        }
        .onDisappear {
            vm.updateSearch("")
        }
    }

    private func browserRow(for sat: SatelliteTrackingViewModel.SatelliteRow, detail: String) -> some View {
        HStack(spacing: 12) {
            Button {
                vm.selectSatellite(sat.id, name: sat.name)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sat.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    Text("NORAD \(sat.id)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                toggleFavorite(for: sat)
            } label: {
                Image(systemName: vm.favoriteSatelliteIds.contains(sat.id) ? "star.fill" : "star")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(vm.favoriteSatelliteIds.contains(sat.id) ? .orange : .secondary)
                    .frame(width: 36, height: 36)
                    .background(Color.secondary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(vm.favoriteSatelliteIds.contains(sat.id) && sat.id == 25544)
            .opacity(vm.favoriteSatelliteIds.contains(sat.id) && sat.id == 25544 ? 0.75 : 1)
        }
        .padding(.vertical, 4)
    }

    private func toggleFavorite(for sat: SatelliteTrackingViewModel.SatelliteRow) {
        if vm.favoriteSatelliteIds.contains(sat.id) {
            vm.removeFavorite(sat.id)
        } else {
            vm.addFavorite(sat.id, name: sat.name)
        }
    }

    private func quickPickDetail(for sat: SatelliteTrackingViewModel.SatelliteRow) -> String {
        if let pass = sat.passes?.first {
            let date = Date(timeIntervalSince1970: TimeInterval(pass.startUTC))
            return "\(Self.timeFormatter.string(from: date)) • max \(Int(pass.maxEl.rounded()))°"
        }
        if let elevation = sat.elevationDeg {
            return String(format: "Visible now • elevation %.0f°", elevation)
        }
        return "Ready to load into the tracking deck."
    }

    private func resultDetail(for sat: SatelliteTrackingViewModel.SatelliteRow) -> String {
        if let pass = sat.passes?.first {
            return "\(Self.timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(pass.startUTC)))) • max \(Int(pass.maxEl.rounded()))°"
        }
        return "Tap to inspect passes, frequencies, and tracking controls."
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
