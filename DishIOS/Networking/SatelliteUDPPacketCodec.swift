import Foundation
import CryptoKit

enum SatelliteMessageType: UInt16 {
    case input = 0x0001
    case heartbeat = 0x0002
    case heartbeatAck = 0x0003
    case rumble = 0x0009
    case sessionClose = 0x000F
}

struct SatelliteUDPPacketCodec {
    let token: UInt32
    let key: SymmetricKey

    func seal(counter: UInt32, direction: UInt8, type: SatelliteMessageType, payload: Data) throws -> Data {
        var header = Data()
        header.appendBE(token)
        header.appendBE(counter)

        var plaintext = Data()
        plaintext.appendBE(type.rawValue)
        plaintext.appendBE(UInt16(payload.count))
        plaintext.append(payload)

        var nonceData = Data([direction])
        nonceData.append(Data(repeating: 0, count: 7))
        nonceData.appendBE(counter)

        let nonce = try ChaChaPoly.Nonce(data: nonceData)
        var aad = Data()
        aad.appendBE(token)

        let sealed = try ChaChaPoly.seal(plaintext, using: key, nonce: nonce, authenticating: aad)

        var packet = header
        packet.append(sealed.ciphertext)
        packet.append(sealed.tag)
        return packet
    }

    func open(_ packet: Data, direction: UInt8) throws -> (counter: UInt32, type: UInt16, payload: Data) {
        guard packet.count >= 8 + 16 else { throw SatelliteCodecError.shortPacket }

        let tokenIn = packet.readBEUInt32(at: 0)
        guard tokenIn == token else { throw SatelliteCodecError.tokenMismatch }

        let counter = packet.readBEUInt32(at: 4)

        let ciphertext = packet.subdata(in: 8..<(packet.count - 16))
        let tag = packet.suffix(16)

        var nonceData = Data([direction])
        nonceData.append(Data(repeating: 0, count: 7))
        nonceData.appendBE(counter)

        let nonce = try ChaChaPoly.Nonce(data: nonceData)
        var aad = Data()
        aad.appendBE(token)

        let box = try ChaChaPoly.SealedBox(
            nonce: nonce,
            ciphertext: ciphertext,
            tag: tag
        )

        let clear = try ChaChaPoly.open(box, using: key, authenticating: aad)
        guard clear.count >= 4 else { throw SatelliteCodecError.shortPlaintext }

        let type = clear.readBEUInt16(at: 0)
        let length = Int(clear.readBEUInt16(at: 2))
        guard clear.count >= 4 + length else { throw SatelliteCodecError.lengthMismatch }

        return (counter, type, clear.subdata(in: 4..<(4 + length)))
    }
}

enum SatelliteCodecError: Error {
    case shortPacket
    case tokenMismatch
    case shortPlaintext
    case lengthMismatch
}

extension Data {
    func readBEUInt16(at offset: Int) -> UInt16 {
        let value = self[offset..<offset+2].reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
        return value
    }

    func readBEUInt32(at offset: Int) -> UInt32 {
        let value = self[offset..<offset+4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return value
    }
}
