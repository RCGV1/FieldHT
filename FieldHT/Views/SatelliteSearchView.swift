import SwiftUI

struct SatelliteSearchView: View {
    @ObservedObject var vm: SatelliteTrackingViewModel
    @State private var searchText: String = ""

    private var trimmed: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        List {
            Section {
                Text("Search by name or NORAD id, then add to Favorites.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if vm.isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Section {
                if trimmed.isEmpty {
                    Text("Start typing to search.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if vm.searchResults.isEmpty, !vm.isSearching {
                    Text("No results.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(vm.searchResults) { sat in
                        Button {
                            if !vm.favoriteSatelliteIds.contains(sat.id) {
                                vm.addFavorite(sat.id, name: sat.name)
                            }
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
                                Image(systemName: vm.favoriteSatelliteIds.contains(sat.id) ? "star.fill" : "star")
                                    .foregroundColor(vm.favoriteSatelliteIds.contains(sat.id) ? .secondary : .orange)
                            }
                        }
                        .disabled(vm.favoriteSatelliteIds.contains(sat.id))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if vm.favoriteSatelliteIds.contains(sat.id), sat.id != 25544 {
                                Button(role: .destructive) {
                                    vm.removeFavorite(sat.id)
                                } label: {
                                    Text("Remove")
                                }
                            }

                            if !vm.favoriteSatelliteIds.contains(sat.id) {
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
                Text("Results")
            }
        }
        .navigationTitle("Add Favorites")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name or NORAD")
        .onChange(of: searchText) {
            vm.updateSearch(searchText)
        }
        .onAppear {
            // Keep search local to this view.
            vm.warmSatelliteSearchIndex()
            searchText = ""
            vm.updateSearch("")
        }
        .onDisappear {
            vm.updateSearch("")
        }
    }
}
