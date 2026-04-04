//
//  GlobalStatusToolbar.swift
//  FieldHT
//
//  Global status toolbar showing battery and TX/RX status
//

import SwiftUI

struct GlobalStatusToolbar: View {
    @EnvironmentObject var radioManager: RadioManager
    
    var statusText: String {
        if radioManager.isTransmitting {
            return "TX"
        } else if radioManager.isReceiving {
            return "RX"
        } else {
            return "Standby"
        }
    }
    
    var statusColor: Color {
        if radioManager.isTransmitting {
            return .red
        } else if radioManager.isReceiving {
            return .green
        } else {
            return .secondary
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(statusColor)
            }
            
            Divider()
                .frame(height: 12)
            
            HStack(spacing: 4) {
                Image(systemName: batteryIcon)
                    .foregroundColor(batteryColor)
                .font(.caption)
                Text("\(radioManager.batteryLevel)%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(format: "(%.1fV)", radioManager.batteryVoltage))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if radioManager.hmBatteryLevel > 0,
               radioManager.radioController?.deviceInfo.hasHandMicrophoneSpeaker == true {
                Divider()
                    .frame(height: 12)

                HStack(spacing: 4) {
                    Image(systemName: "mic.fill")
                        .font(.caption)
                        .foregroundColor(radioManager.hmBatteryLevel > 25 ? .green : (radioManager.hmBatteryLevel > 10 ? .orange : .red))
                    Text("\(radioManager.hmBatteryLevel)%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule())
    }
    
    private var batteryIcon: String {
        let level = radioManager.batteryLevel
        if level > 75 { return "battery.100" }
        if level > 50 { return "battery.75" }
        if level > 25 { return "battery.50" }
        if level > 10 { return "battery.25" }
        return "battery.0"
    }

    private var batteryColor: Color {
        let level = radioManager.batteryLevel
        if level > 25 { return .green }
        if level > 10 { return .orange }
        return .red
    }
}
