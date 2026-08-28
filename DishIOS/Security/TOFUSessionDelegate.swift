import Foundation
import Security
import CryptoKit

final class TOFUSessionDelegate: NSObject, URLSessionDelegate {
    private let machineID: String
    private let defaults = UserDefaults.standard

    init(machineID: String) {
        self.machineID = machineID
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let certificate = SecTrustGetCertificateAtIndex(trust, 0),
              let certificateData = SecCertificateCopyData(certificate) as Data? else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let fingerprint = SHA256.hash(data: certificateData)
            .map { String(format: "%02x", $0) }
            .joined()

        let key = "dish.tofu.\(machineID)"

        if let pinned = defaults.string(forKey: key) {
            guard pinned == fingerprint else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        } else {
            defaults.set(fingerprint, forKey: key)
        }

        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
