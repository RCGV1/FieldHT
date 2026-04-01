//
//  NotConnectedView.swift
//  FieldHT
//
//  Shared "no radio connected" screen shown in Radio Control and Settings.
//  Previews the app's feature set and surfaces the support link.
//

import SwiftUI

struct NotConnectedView: View {

    private struct Feature: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let title: String
        let detail: String
    }

    private let features: [Feature] = [
        Feature(icon: "list.bullet.rectangle.portrait", color: .blue,
                title: "Zones & Channels",
                detail: "30 channels across up to 8 named memory groups"),
        Feature(icon: "waveform.path.badge.plus", color: .orange,
                title: "VFO Free Tune",
                detail: "Tune freely across any amateur band"),
        Feature(icon: "location.fill", color: .green,
                title: "APRS Beaconing",
                detail: "Broadcast your position over packet radio"),
        Feature(icon: "globe.americas.fill", color: .indigo,
                title: "Satellite Tracking",
                detail: "Live Doppler-corrected pass predictions"),
        Feature(icon: "mic.fill", color: .purple,
                title: "Siri Shortcuts",
                detail: "Switch zones and channels hands-free"),
        Feature(icon: "sparkles", color: .cyan,
                title: "AI Channel Import",
                detail: "Parse any file with Apple Intelligence"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                heroSection
                featuresGrid
                connectHint
                Divider()
                    .padding(.horizontal)
                supportCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 96, height: 96)
                Image(systemName: "radio")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                Text("FieldHT")
                    .font(.largeTitle.bold())

                Text("Full radio control over Bluetooth.\nConnect your UV-PRO to unlock everything below.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Feature Grid

    private var featuresGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ForEach(features) { f in
                featureCard(f)
            }
        }
    }

    private func featureCard(_ f: Feature) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: f.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(f.color)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(f.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Text(f.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Connect Hint

    private var connectHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Tap the **Connect** tab to pair your radio")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Support Card

    private var supportCard: some View {
        SupportDeveloperRow()
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        NotConnectedView()
            .navigationTitle("Radio Control")
    }
}
