//
//  RadioData.swift
//  FieldHT
//
//  Created by Benjamin Faershtein on 12/17/25.
//
import Foundation
import SwiftData

@Model
public final class RadioData {
    public var id: UUID = UUID()
    
    /// Region → Channels
    public var channelsByRegion: [Int: [Channel]] = [:]
    
    public init() { } // Empty init for SwiftData
    
    public init(channelsByRegion: [Int: [Channel]] = [:]) {
        self.channelsByRegion = channelsByRegion
    }
    
    // MARK: - Mutations
    
    public func addChannel(_ channel: Channel, to region: Int) {
        channelsByRegion[region, default: []].append(channel)
    }
    
    public func setChannel(_ channel: Channel, at index: Int, in region: Int) {
        guard var channels = channelsByRegion[region],
              channels.indices.contains(index) else { return }
        channels[index] = channel
        channelsByRegion[region] = channels
    }
    
    public func removeChannel(at index: Int, in region: Int) {
        guard var channels = channelsByRegion[region],
              channels.indices.contains(index) else { return }
        channels.remove(at: index)
        if channels.isEmpty {
            channelsByRegion.removeValue(forKey: region)
        } else {
            channelsByRegion[region] = channels
        }
    }
    
    public func channels(for region: Int) -> [Channel] {
        channelsByRegion[region] ?? []
    }
    
    public func clearRegion(_ region: Int) {
        channelsByRegion.removeValue(forKey: region)
    }
    
    public func clearAll() {
        channelsByRegion.removeAll()
    }
}
