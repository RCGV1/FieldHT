import Foundation

/// Bit stream for reading/writing bit-aligned data
public struct BitStream {
    private var bits: [Bool]
    private var position: Int
    
    public init(data: Data = Data()) {
        var bitArray: [Bool] = []
        for byte in data {
            for i in 0..<8 {
                bitArray.append((byte & (1 << (7 - i))) != 0)
            }
        }
        self.bits = bitArray
        self.position = 0
    }
    
    public var remaining: Int {
        return bits.count - position
    }
    
    public mutating func readBits(_ count: Int) throws -> [Bool] {
        guard position + count <= bits.count else {
            throw BitfieldError.endOfStream
        }
        let result = Array(bits[position..<(position + count)])
        position += count
        return result
    }
    
    public mutating func readInt(_ bitCount: Int) throws -> Int {
        let bitArray = try readBits(bitCount)
        var value = 0
        for (index, bit) in bitArray.enumerated() {
            if bit {
                value |= (1 << (bitCount - 1 - index))
            }
        }
        return value
    }
    
    public mutating func readBool() throws -> Bool {
        return try readInt(1) != 0
    }
    
    public mutating func readBytes(_ byteCount: Int) throws -> Data {
        let bitCount = byteCount * 8
        let bitArray = try readBits(bitCount)
        var data = Data()
        for i in 0..<byteCount {
            var byte: UInt8 = 0
            for j in 0..<8 {
                if bitArray[i * 8 + j] {
                    byte |= (1 << (7 - j))
                }
            }
            data.append(byte)
        }
        return data
    }
    
    public mutating func writeBits(_ bits: [Bool]) {
        self.bits.append(contentsOf: bits)
    }
    
    public mutating func writeInt(_ value: Int, bitCount: Int) {
        var bits: [Bool] = []
        for i in 0..<bitCount {
            bits.append((value & (1 << (bitCount - 1 - i))) != 0)
        }
        writeBits(bits)
    }
    
    public mutating func writeBool(_ value: Bool) {
        writeInt(value ? 1 : 0, bitCount: 1)
    }
    
    public mutating func writeBytes(_ data: Data) {
        for byte in data {
            for i in 0..<8 {
                writeBool((byte & (1 << (7 - i))) != 0)
            }
        }
    }
    
    public func toData() -> Data {
        var data = Data()
        let byteCount = (bits.count + 7) / 8
        for i in 0..<byteCount {
            var byte: UInt8 = 0
            for j in 0..<8 {
                let bitIndex = i * 8 + j
                if bitIndex < bits.count && bits[bitIndex] {
                    byte |= (1 << (7 - j))
                }
            }
            data.append(byte)
        }
        return data
    }
}

public enum BitfieldError: Error {
    case endOfStream
    case invalidValue
    case decodeError(String)
}

