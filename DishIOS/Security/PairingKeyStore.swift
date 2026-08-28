import Foundation
import Security

enum PairingKeyStore {
    static func save(_ hexKey: String, machineID: String) throws {
        let account = "satellite.\(machineID)"
        let data = Data(hexKey.utf8)

        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "DishIOS",
            kSecAttrAccount: account
        ] as CFDictionary)

        let status = SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "DishIOS",
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ] as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw PairingKeyStoreError.keychain(status)
        }
    }

    static func load(machineID: String) throws -> String? {
        let account = "satellite.\(machineID)"
        var item: CFTypeRef?

        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "DishIOS",
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary, &item)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw PairingKeyStoreError.keychain(status)
        }

        return value
    }
}

enum PairingKeyStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "Keychain error: \(status)"
        }
    }
}
