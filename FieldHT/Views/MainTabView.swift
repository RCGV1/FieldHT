//
//  MainTabView.swift
//  FieldHT
//
//  Created by Benjamin Faershtein on 12/13/25.
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @EnvironmentObject private var radioManager: RadioManager

    var body: some View {
        TabView {
            tabContainer {
                RadioControlView()
            }
            .tabItem {
                Label("Radio", systemImage: "radio")
            }

            tabContainer {
                ConnectView()
            }
            .tabItem {
                Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
            }

            tabContainer {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
    }

    private func tabContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        if radioManager.isConnected {
                            GlobalStatusToolbar()
                                .environmentObject(radioManager)
                        }
                    }
                }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(RadioManager())
}
