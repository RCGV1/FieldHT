import Foundation

/// Modulation type
public enum ModulationType: String, Codable, CaseIterable {
    case am = "AM"
    case fm = "FM"
    case dmr = "DMR"
    
    /// Convert from protocol integer value
    public static func fromProtocolValue(_ value: Int) -> ModulationType {
        switch value {
        case 0: return .fm
        case 1: return .am
        case 2: return .dmr
        default: return .fm
        }
    }
    
    /// Convert to protocol integer value
    public func toProtocolValue() -> Int {
        switch self {
        case .fm: return 0
        case .am: return 1
        case .dmr: return 2
        }
    }
}

/// Bandwidth type
public enum BandwidthType: String, Codable, CaseIterable {
    case narrow = "NARROW"
    case wide = "WIDE"
    
    /// Convert from protocol integer value
    public static func fromProtocolValue(_ value: Int) -> BandwidthType {
        switch value {
        case 0: return .narrow
        case 1: return .wide
        default: return .narrow
        }
    }
    
    /// Convert to protocol integer value
    public func toProtocolValue() -> Int {
        switch self {
        case .narrow: return 0
        case .wide: return 1
        }
    }
}

/// Digital Coded Squelch (DCS)
public struct DCS: Codable, Equatable, Hashable {
    public let n: Int
    
    public init(n: Int) {
        self.n = n
    }
}

/// Sub-audio type (can be a frequency, DCS, or nil)
public enum SubAudio: Codable, Equatable, Hashable {
    case frequency(Double)
    case dcs(DCS)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dcs = try? container.decode(DCS.self) {
            self = .dcs(dcs)
        } else if let freq = try? container.decode(Double.self) {
            self = .frequency(freq)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid SubAudio")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .frequency(let freq):
            try container.encode(freq)
        case .dcs(let dcs):
            try container.encode(dcs)
        }
    }
}

/// Radio channel configuration
public struct Channel: Codable, Equatable {
    public var channelID: Int
    public var txMod: ModulationType
    public var txFreq: Double
    public var rxMod: ModulationType
    public var rxFreq: Double
    public var txSubAudio: SubAudio?
    public var rxSubAudio: SubAudio?
    public var scan: Bool
    public var txAtMaxPower: Bool
    public var talkAround: Bool
    public var bandwidth: BandwidthType
    public var preDeEmphBypass: Bool
    public var sign: Bool
    public var txAtMedPower: Bool
    public var txDisable: Bool
    public var fixedFreq: Bool
    public var fixedBandwidth: Bool
    public var fixedTxPower: Bool
    public var mute: Bool
    public var name: String
    
    public init(
        channelID: Int,
        txMod: ModulationType,
        txFreq: Double,
        rxMod: ModulationType,
        rxFreq: Double,
        txSubAudio: SubAudio?,
        rxSubAudio: SubAudio?,
        scan: Bool,
        txAtMaxPower: Bool,
        talkAround: Bool,
        bandwidth: BandwidthType,
        preDeEmphBypass: Bool,
        sign: Bool,
        txAtMedPower: Bool,
        txDisable: Bool,
        fixedFreq: Bool,
        fixedBandwidth: Bool,
        fixedTxPower: Bool,
        mute: Bool,
        name: String
    ) {
        self.channelID = channelID
        self.txMod = txMod
        self.txFreq = txFreq
        self.rxMod = rxMod
        self.rxFreq = rxFreq
        self.txSubAudio = txSubAudio
        self.rxSubAudio = rxSubAudio
        self.scan = scan
        self.txAtMaxPower = txAtMaxPower
        self.talkAround = talkAround
        self.bandwidth = bandwidth
        self.preDeEmphBypass = preDeEmphBypass
        self.sign = sign
        self.txAtMedPower = txAtMedPower
        self.txDisable = txDisable
        self.fixedFreq = fixedFreq
        self.fixedBandwidth = fixedBandwidth
        self.fixedTxPower = fixedTxPower
        self.mute = mute
        self.name = name
    }
}

