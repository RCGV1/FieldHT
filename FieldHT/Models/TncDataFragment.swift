import Foundation

/// TNC data fragment
public struct TncDataFragment: Codable, Equatable {
    public static let maximumDataLength = 50

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

    /// Splits an AX.25 packet into the UV-PRO TNC command's bounded payloads.
    public static func fragments(for data: Data, channelID: Int? = nil) -> [TncDataFragment] {
        guard !data.isEmpty else { return [] }

        return stride(from: 0, to: data.count, by: maximumDataLength).enumerated().map { index, offset in
            let end = min(offset + maximumDataLength, data.count)
            return TncDataFragment(
                isFinalFragment: end == data.count,
                fragmentID: index,
                data: Data(data[offset..<end]),
                channelID: channelID
            )
        }
    }
}
