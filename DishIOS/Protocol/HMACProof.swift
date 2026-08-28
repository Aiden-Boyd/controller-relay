import Foundation
import CryptoKit

enum HMACProof {
    static func make(pairingKeyHex: String, deviceID: String) throws -> String {
        let keyData = try Hex.decode(pairingKeyHex)
        let key = SymmetricKey(data: keyData)
        let message = Data(("satellite-proof:" + deviceID).utf8)
        let code = HMAC<SHA256>.authenticationCode(for: message, using: key)
        return code.map { String(format: "%02x", $0) }.joined()
    }
}
