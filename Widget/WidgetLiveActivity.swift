import SwiftUI
import ActivityKit
import WidgetKit

struct FieldHTSatelliteLiveActivityWidget: Widget {
    private static let accent = Color.orange

    private static func formatDopplerShift(_ shiftHz: Int) -> String {
        let absHz = abs(shiftHz)
        let sign = (shiftHz >= 0) ? "+" : "-"
        if absHz >= 1000 {
            let khz = Double(absHz) / 1000.0
            return String(format: "%@%.2fk", sign, khz)
        }
        return "\(sign)\(absHz)"
    }

    private static func formatUpdatedAgo(updatedAtUnix: Int) -> String? {
        guard updatedAtUnix > 0 else { return nil }
        let now = Int(Date().timeIntervalSince1970)
        let dt = max(0, now - updatedAtUnix)
        if dt < 60 { return "Upd \(dt)s" }
        let m = dt / 60
        if m < 60 { return "Upd \(m)m" }
        let h = m / 60
        return "Upd \(h)h"
    }

    private static func ordinalDirection(fromAzimuthDegrees az: Int) -> String {
        // 8-wind compass.
        let deg = (az % 360 + 360) % 360
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let idx = Int((Double(deg) + 22.5) / 45.0) % 8
        return dirs[idx]
    }

    private static func formatDurationShort(from countdown: String?) -> String? {
        // ViewModel provides e.g. "In range now, ends in 4m 02s" or "In range in 10m 05s".
        // We compress to the most actionable tail.
        guard let countdown, !countdown.isEmpty else { return nil }
        if let r = countdown.range(of: "ends in ") {
            return "Ends in " + String(countdown[r.upperBound...])
        }
        if let r = countdown.range(of: "In range in ") {
            return "In " + String(countdown[r.upperBound...])
        }
        return countdown
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SatelliteTrackingAttributes.self) { context in
            // Lock screen / banner
            let dir = Self.ordinalDirection(fromAzimuthDegrees: context.state.azDeg)
            let timeLine = Self.formatDurationShort(from: context.state.countdown)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 6) {
                        Image(systemName: "satellite.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Self.accent)
                        Text(context.state.name)
                            .lineLimit(1)
                    }
                    .font(.headline)
                    Spacer(minLength: 8)
                    Text("El \(context.state.elDeg)°")
                        .font(.headline)
                        .monospacedDigit()
                }

                HStack(spacing: 10) {
                    Text("\(dir)  \(context.state.azDeg)°")
                        .monospacedDigit()
                    Text("R \(context.state.rangeKm) km")
                        .monospacedDigit()
                    Text("Dop \(Self.formatDopplerShift(context.state.dopplerShiftHz))")
                        .monospacedDigit()
                    if let upd = Self.formatUpdatedAgo(updatedAtUnix: context.state.updatedAtUnix) {
                        Text(upd)
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.78))

                if let timeLine {
                    Text(timeLine)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                }

                HStack(spacing: 10) {
                    Text(String(format: "RX %.3f", Double(context.state.rxMHzX1000) / 1000.0))
                        .monospacedDigit()
                    Text(String(format: "TX %.3f", Double(context.state.txMHzX1000) / 1000.0))
                        .monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.78))
            }
            .padding(12)
            .foregroundStyle(.white)
            .activityBackgroundTint(.black.opacity(0.82))
            .activitySystemActionForegroundColor(Self.accent)
        } dynamicIsland: { context in
            let dir = Self.ordinalDirection(fromAzimuthDegrees: context.state.azDeg)
            let timeLine = Self.formatDurationShort(from: context.state.countdown) ?? ""
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "satellite.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Self.accent)
                            Text(context.state.name)
                                .lineLimit(1)
                        }
                        .font(.headline)
                        Text(timeLine)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("El \(context.state.elDeg)°")
                            .font(.headline)
                            .monospacedDigit()
                        Text("\(dir) \(context.state.azDeg)°")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("R \(context.state.rangeKm) km")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                            Text("Dop \(Self.formatDopplerShift(context.state.dopplerShiftHz))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                            Text(String(format: "RX %.3f", Double(context.state.rxMHzX1000) / 1000.0))
                                .font(.caption)
                                .monospacedDigit()
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 4) {
                            if let upd = Self.formatUpdatedAgo(updatedAtUnix: context.state.updatedAtUnix) {
                                Text(upd)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                            Text(String(format: "TX %.3f", Double(context.state.txMHzX1000) / 1000.0))
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }
                }
            } compactLeading: {
                Text(dir)
                    .font(.caption)
            } compactTrailing: {
                Text(timeLine.isEmpty ? "El \(context.state.elDeg)°" : timeLine)
                    .font(.caption2)
                    .lineLimit(1)
            } minimal: {
                Image(systemName: "satellite.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Self.accent)
            }
        }
    }
}
