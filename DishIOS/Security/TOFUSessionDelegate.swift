import Foundation
import Security
import CryptoKit

final class TOFUSessionDelegate: NSObject, URLSessionDelegate {
    private let machineID: String

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
              let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let certificate = certificates.first else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let certificateData = SecCertificateCopyData(certificate) as Data
        let fingerprint = SHA256.hash(data: certificateData)
            .map { String(format: "%02x", $0) }
            .joined()

        let key = "dish.tofu.\(machineID)"
        let defaults = UserDefaults.standard

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
