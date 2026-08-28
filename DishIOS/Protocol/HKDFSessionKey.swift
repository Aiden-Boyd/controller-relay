import Foundation
import CryptoKit

enum HKDFSessionKey {
    static func derive(pairingKeyHex: String, sessionSaltHex: String, tokenHex: String) throws -> SymmetricKey {
        let ikm = SymmetricKey(data: try Hex.decode(pairingKeyHex))
        let salt = try Hex.decode(sessionSaltHex)
        let token = try Hex.decode(tokenHex)

        var info = Data("satellite-session-v1".utf8)
        info.append(token)

        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm,
            salt: salt,
            info: info,
            outputByteCount: 32
        )
    }
}
