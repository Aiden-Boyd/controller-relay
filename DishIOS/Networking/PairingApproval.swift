import Foundation

enum PairingApproval {
    static func generatePIN() -> String {
        String(format: "%04d", Int.random(in: 0...9999))
    }

    static func validSharedKey(_ value: String?) -> String? {
        guard let value, value.count == 64 else { return nil }
        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return value
    }
}

enum PairApprovalStatus: Equatable {
    case approved(String)
    case pending
    case declined
}
