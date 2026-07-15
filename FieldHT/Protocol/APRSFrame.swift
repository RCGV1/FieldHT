import Foundation

/// An AX.25 address as carried by the UV-PRO TNC data channel.
public struct APRSAddress: Equatable, Sendable {
    public let callsign: String
    public let ssid: Int
    public let hasBeenRepeated: Bool

    public init(_ value: String, hasBeenRepeated: Bool = false) {
        let components = value
            .uppercased()
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)

        self.callsign = String(components.first ?? "")
        self.ssid = components.count == 2 ? Int(components[1]) ?? 0 : 0
        self.hasBeenRepeated = hasBeenRepeated
    }

    public var displayValue: String {
        ssid == 0 ? callsign : "\(callsign)-\(ssid)"
    }

    fileprivate var isValid: Bool {
        (1...6).contains(callsign.count) &&
            callsign.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } &&
            (0...15).contains(ssid)
    }
}

/// A UI-frame APRS packet that can move between the UV-PRO TNC and APRS-IS.
public struct APRSFrame: Equatable, Sendable {
    public let source: APRSAddress
    public let destination: APRSAddress
    public let path: [APRSAddress]
    public let information: String

    public init(source: String, destination: String, path: [APRSAddress] = [], information: String) {
        self.source = APRSAddress(source)
        self.destination = APRSAddress(destination)
        self.path = path
        self.information = information
    }

    private init(source: APRSAddress, destination: APRSAddress, path: [APRSAddress], information: String) {
        self.source = source
        self.destination = destination
        self.path = path
        self.information = information
    }

    /// Decodes the standard AX.25 UI frame contained in a completed UV-PRO TNC packet.
    public init?(ax25Data: Data) {
        let bytes = Array(ax25Data)
        guard bytes.count >= 16, bytes[0] & 0x01 == 0 else { return nil }

        var offset = 0
        var addresses: [APRSAddress] = []
        var isLastAddress = false

        while !isLastAddress {
            guard offset + 7 <= bytes.count, addresses.count < 10 else { return nil }

            let addressBytes = Array(bytes[offset..<(offset + 7)])
            guard let address = Self.decodeAddress(addressBytes, isRepeater: addresses.count >= 2) else { return nil }
            addresses.append(address)
            isLastAddress = addressBytes[6] & 0x01 == 0x01
            offset += 7
        }

        guard addresses.count >= 2, offset + 2 <= bytes.count else { return nil }
        guard bytes[offset] == 0x03, bytes[offset + 1] == 0xF0 else { return nil }

        let informationBytes = Data(bytes[(offset + 2)...])
        guard
            let information = String(data: informationBytes, encoding: .ascii),
            Self.isPrintableInformation(information)
        else {
            return nil
        }

        self.init(
            source: addresses[1],
            destination: addresses[0],
            path: Array(addresses.dropFirst(2)),
            information: information
        )
    }

    /// Parses an APRS-IS packet line for safe injection into the radio TNC.
    public init?(aprsISLine: String) {
        let line = aprsISLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.hasPrefix("#"), let separator = line.firstIndex(of: ">"), let payload = line.firstIndex(of: ":") else {
            return nil
        }
        guard separator > line.startIndex, payload > separator else { return nil }

        let source = APRSAddress(String(line[..<separator]))
        let route = line[line.index(after: separator)..<payload].split(separator: ",", omittingEmptySubsequences: false)
        guard let destinationText = route.first, !destinationText.isEmpty else { return nil }

        let destination = APRSAddress(String(destinationText))
        let path = route
            .dropFirst()
            .prefix(8)
            .compactMap { component -> APRSAddress? in
                let value = String(component)
                guard !Self.isInternetRoutingComponent(value) else { return nil }
                let hasBeenRepeated = value.hasSuffix("*")
                let address = APRSAddress(hasBeenRepeated ? String(value.dropLast()) : value, hasBeenRepeated: hasBeenRepeated)
                return address.isValid ? address : nil
            }
        let information = String(line[line.index(after: payload)...])

        guard source.isValid, destination.isValid, Self.isPrintableInformation(information) else { return nil }
        self.init(source: source, destination: destination, path: path, information: information)
    }

    /// AX.25 UI bytes accepted by the UV-PRO's HT_SEND_DATA command.
    public var ax25Data: Data {
        guard source.isValid, destination.isValid, path.allSatisfy(\.isValid), path.count <= 8, Self.isPrintableInformation(information) else {
            return Data()
        }

        let addresses = [destination, source] + path
        var data = Data()
        for (index, address) in addresses.enumerated() {
            data.append(contentsOf: Self.encodeAddress(
                address,
                isLast: index == addresses.count - 1,
                isDestination: index == 0
            ))
        }
        data.append(0x03)
        data.append(0xF0)
        data.append(contentsOf: information.utf8)
        return data
    }

    /// Vendor-compatible APRS-IS rendering. The qAO marker attributes the RF-to-IS hop to this gateway.
    public func aprsISLine(gatewayCallsign: String) -> String? {
        let gateway = APRSAddress(gatewayCallsign)
        guard gateway.isValid, isSafeToGate else { return nil }

        let renderedPath = path.map { address in
            address.displayValue + (address.hasBeenRepeated ? "*" : "")
        }
        let route = ([destination.displayValue] + renderedPath + ["qAO", gateway.displayValue]).joined(separator: ",")
        return "\(source.displayValue)>\(route):\(information)"
    }

    /// APRS-IS path components that explicitly prohibit RF-to-IS relaying.
    public var isSafeToGate: Bool {
        let blocked = Set(["NOGATE", "RFONLY", "TCPIP", "TCPXX"])
        return !path.contains { blocked.contains($0.callsign) }
    }

    private static func decodeAddress(_ bytes: [UInt8], isRepeater: Bool) -> APRSAddress? {
        guard bytes.count == 7 else { return nil }
        let callBytes = bytes.prefix(6).map { $0 >> 1 }
        guard callBytes.allSatisfy({ $0 == 0x20 || ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) }) else {
            return nil
        }
        let callsign = String(bytes: callBytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
        let ssid = Int((bytes[6] >> 1) & 0x0F)
        let value = ssid == 0 ? callsign : "\(callsign)-\(ssid)"
        let address = APRSAddress(value, hasBeenRepeated: isRepeater && (bytes[6] & 0x80 != 0))
        return address.isValid ? address : nil
    }

    private static func encodeAddress(_ address: APRSAddress, isLast: Bool, isDestination: Bool) -> [UInt8] {
        let callsign = Array(address.callsign.padding(toLength: 6, withPad: " ", startingAt: 0).utf8.prefix(6))
        var bytes = callsign.map { $0 << 1 }
        var flags = UInt8((address.ssid << 1) | 0x60)
        if isDestination || address.hasBeenRepeated {
            flags |= 0x80
        }
        if isLast {
            flags |= 0x01
        }
        bytes.append(flags)
        return bytes
    }

    private static func isInternetRoutingComponent(_ value: String) -> Bool {
        let callsign = APRSAddress(value).callsign
        return callsign.hasPrefix("Q") && callsign.count == 3 || callsign == "TCPIP" || callsign == "TCPXX"
    }

    private static func isPrintableInformation(_ information: String) -> Bool {
        information.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value <= 0x7E }
    }
}

/// Reassembles the ordered TNC fragments delivered by the radio's DATA_RXD notification.
public struct TncPacketAssembler: Sendable {
    private static let maximumPacketSize = 330
    private var pendingData = Data()
    private var expectedFragmentID: Int?

    public init() {}

    public mutating func append(_ fragment: TncDataFragment) -> Data? {
        if fragment.fragmentID == 0 {
            pendingData.removeAll(keepingCapacity: true)
            expectedFragmentID = 0
        }

        guard expectedFragmentID == fragment.fragmentID else {
            pendingData.removeAll(keepingCapacity: false)
            expectedFragmentID = nil
            return nil
        }

        guard pendingData.count + fragment.data.count <= Self.maximumPacketSize else {
            pendingData.removeAll(keepingCapacity: false)
            expectedFragmentID = nil
            return nil
        }

        pendingData.append(fragment.data)

        if fragment.isFinalFragment {
            let completed = pendingData
            pendingData.removeAll(keepingCapacity: true)
            expectedFragmentID = nil
            return completed
        }

        expectedFragmentID = (fragment.fragmentID + 1) & 0x3F
        return nil
    }
}
