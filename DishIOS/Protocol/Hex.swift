import Foundation

enum Hex {
    static func decode(_ string: String) throws -> Data {
        guard string.count % 2 == 0 else { throw HexError.invalidLength }
        var data = Data()
        data.reserveCapacity(string.count / 2)

        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            let byteString = String(string[index..<next])
            guard let byte = UInt8(byteString, radix: 16) else {
                throw HexError.invalidCharacter
            }
            data.append(byte)
            index = next
        }

        return data
    }

    static func encode(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

enum HexError: Error {
    case invalidLength
    case invalidCharacter
}
