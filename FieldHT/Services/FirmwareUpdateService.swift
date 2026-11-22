import Foundation

public struct RadioFirmwareUpdate: Equatable, Sendable {
    public let version: Int
    public let releaseNotes: String
    public let releaseDate: Date?

    public var versionDescription: String { Self.describe(version) }

    public static func describe(_ version: Int) -> String {
        "\((version >> 8) & 15).\((version >> 4) & 15).\(version & 15)"
    }
}

public enum FirmwareCheckError: LocalizedError {
    case invalidProduct
    case invalidResponse
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .invalidProduct: return "Connect a radio before checking its firmware."
        case .invalidResponse: return "The firmware server returned an invalid response."
        case .server(let message): return "Firmware check failed: \(message)"
        }
    }
}

/// Read-only unary gRPC request; no firmware is downloaded or written to the radio.
public struct FirmwareUpdateService {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func check(productID: Int) async throws -> RadioFirmwareUpdate? {
        let request = try Self.request(productID: productID)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/grpc") == true else {
            throw FirmwareCheckError.invalidResponse
        }
        if let status = http.value(forHTTPHeaderField: "grpc-status"), status != "0" {
            throw FirmwareCheckError.server(http.value(forHTTPHeaderField: "grpc-message")?.removingPercentEncoding ?? "gRPC status \(status)")
        }
        return try Self.decodeResponse(data)
    }

    public static func request(productID: Int) throws -> URLRequest {
        guard (1...65535).contains(productID) else { throw FirmwareCheckError.invalidProduct }
        var request = URLRequest(url: URL(string: "https://rpc.benshikj.com:800/benshikj.DeviceManagement/CheckFirmwareUpdate")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/grpc", forHTTPHeaderField: "Content-Type")
        request.setValue("trailers", forHTTPHeaderField: "TE")
        request.setValue("identity", forHTTPHeaderField: "grpc-accept-encoding")
        // Request field 1 = product ID. Version 0 requests the latest stable
        // release and is omitted by proto3, as is the false beta flag.
        let protobuf = Data([0x08] + varint(UInt64(productID)))
        let count = UInt32(protobuf.count)
        request.httpBody = Data([0, UInt8(count >> 24), UInt8((count >> 16) & 255), UInt8((count >> 8) & 255), UInt8(count & 255)]) + protobuf
        return request
    }

    public static func decodeResponse(_ data: Data) throws -> RadioFirmwareUpdate? {
        let bytes = Array(data)
        guard bytes.count >= 5, bytes[0] == 0 else { throw FirmwareCheckError.invalidResponse }
        let count = Int(bytes[1]) << 24 | Int(bytes[2]) << 16 | Int(bytes[3]) << 8 | Int(bytes[4])
        guard count <= 1_048_576, count == bytes.count - 5 else { throw FirmwareCheckError.invalidResponse }
        let fields = try protobufFields(Array(bytes.dropFirst(5)))
        guard let descriptor = fields.first(where: { $0.number == 1 && $0.wire == 2 }) else {
            guard fields.isEmpty else { throw FirmwareCheckError.invalidResponse }
            return nil
        }
        let firmware = try protobufFields(descriptor.bytes)
        guard let versionField = firmware.first(where: { $0.number == 1 && $0.wire == 0 }),
              let version = Int(exactly: versionField.value), version > 0 else { throw FirmwareCheckError.invalidResponse }
        let notesBytes = firmware.first(where: { $0.number == 4 && $0.wire == 2 })?.bytes ?? []
        guard let notes = String(bytes: notesBytes, encoding: .utf8) else { throw FirmwareCheckError.invalidResponse }
        let timestamp = firmware.first(where: { $0.number == 5 && $0.wire == 0 })?.value ?? 0
        return RadioFirmwareUpdate(version: version, releaseNotes: notes, releaseDate: timestamp == 0 ? nil : Date(timeIntervalSince1970: Double(timestamp)))
    }

    private struct Field {
        let number: Int
        let wire: UInt64
        let value: UInt64
        let bytes: [UInt8]
    }

    private static func protobufFields(_ bytes: [UInt8]) throws -> [Field] {
        var index = 0
        var fields: [Field] = []
        func readVarint() throws -> UInt64 {
            var value: UInt64 = 0
            for shift in stride(from: 0, through: 63, by: 7) {
                guard index < bytes.count else { throw FirmwareCheckError.invalidResponse }
                let byte = bytes[index]
                index += 1
                if shift == 63 && byte > 1 { throw FirmwareCheckError.invalidResponse }
                value |= UInt64(byte & 127) << shift
                if byte & 128 == 0 { return value }
            }
            throw FirmwareCheckError.invalidResponse
        }
        while index < bytes.count {
            let tag = try readVarint()
            guard tag >> 3 > 0, let number = Int(exactly: tag >> 3) else { throw FirmwareCheckError.invalidResponse }
            let wire = tag & 7
            if wire == 0 {
                fields.append(Field(number: number, wire: wire, value: try readVarint(), bytes: []))
            } else {
                let length: Int
                switch wire {
                case 1: length = 8
                case 2:
                    guard let count = Int(exactly: try readVarint()) else { throw FirmwareCheckError.invalidResponse }
                    length = count
                case 5: length = 4
                default: throw FirmwareCheckError.invalidResponse
                }
                guard length <= bytes.count - index else { throw FirmwareCheckError.invalidResponse }
                fields.append(Field(number: number, wire: wire, value: 0, bytes: Array(bytes[index..<(index + length)])))
                index += length
            }
        }
        return fields
    }

    private static func varint(_ value: UInt64) -> [UInt8] {
        var value = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value & 127)
            value >>= 7
            if value != 0 { byte |= 128 }
            bytes.append(byte)
        } while value != 0
        return bytes
    }
}
