//
//  NetworkMonitor.swift
//  FieldHT
//

import Foundation
import Network
import Combine

/// Simple network connectivity monitor
@MainActor
public class NetworkMonitor: ObservableObject {
    public static let shared = NetworkMonitor()
    
    @Published public private(set) var isConnected: Bool = false
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    private init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            // Capture the value before hopping to MainActor to avoid a mutable
            // self capture in a Sendable closure (Swift 6 error).
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }
    
    /// Check if internet is available (synchronous check)
    public func checkConnectivity() -> Bool {
        return isConnected
    }
}
