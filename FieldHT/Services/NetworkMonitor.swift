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
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
    
    /// Check if internet is available (synchronous check)
    public func checkConnectivity() -> Bool {
        return isConnected
    }
}
