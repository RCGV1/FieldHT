//
//  MainTabView.swift
//  FieldHT
//
//  Created by Benjamin Faershtein on 12/13/25.
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @StateObject private var radioManager = RadioManager()

      var body: some View {
          NavigationStack {
              TabView {

                  RadioControlView()
                  .tabItem {
                      Label("Radio", systemImage: "radio")
                  }

                  ConnectView()
                      .tabItem {
                          Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
                      }

                  SettingsView()
                      .tabItem {
                          Label("Settings", systemImage: "gearshape.fill")
                      }
              }
              .environmentObject(radioManager)
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
  }
