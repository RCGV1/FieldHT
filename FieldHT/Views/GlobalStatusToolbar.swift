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
            // TX/RX Status
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
            
            // Battery
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
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
    
    private var batteryIcon: String {
        if radioManager.batteryLevel > 75 {
            return "battery.100"
        } else if radioManager.batteryLevel > 50 {
            return "battery.75"
        } else if radioManager.batteryLevel > 25 {
            return "battery.50"
        } else {
            return "battery.25"
        }
    }
    
    private var batteryColor: Color {
        if radioManager.batteryLevel > 25 {
            return .green
        } else {
            return .red
        }
    }
}
