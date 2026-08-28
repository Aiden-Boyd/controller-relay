import Foundation

enum DeviceIdentity {
    private static let key = "dish.deviceId"

    static func current() -> String {
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }

        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}
