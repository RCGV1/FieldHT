import Foundation

/// TNC data fragment
public struct TncDataFragment: Codable, Equatable {
    public let isFinalFragment: Bool
    public let fragmentID: Int
    public let data: Data
    public let channelID: Int?
    
    public init(
        isFinalFragment: Bool,
        fragmentID: Int,
        data: Data,
        channelID: Int? = nil
    ) {
        self.isFinalFragment = isFinalFragment
        self.fragmentID = fragmentID
        self.data = data
        self.channelID = channelID
    }
}

