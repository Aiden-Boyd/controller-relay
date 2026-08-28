import Foundation
import Network
import UIKit

struct PairingResult: Decodable {
    let ok: Bool
    let message: String?
    let sharedKey: String
    let protocolVersion: Int
}

private struct PairingRequest: Encodable {
    let deviceId: String
    let deviceName: String
    let pin: String
    let protocolVersion: Int
}

final class SatellitePairingClient: NSObject {
    func pair(host: SatelliteHost, pin: String) async throws -> PairingResult {
        guard pin.count == 4, pin.allSatisfy(\.isNumber) else {
            throw PairingError.invalidPIN
        }

        let resolved = try await SatelliteEndpointResolver.resolve(host.endpoint)
        let hostString = resolved.host.contains(":") ? "[\(resolved.host)]" : resolved.host
        let deviceName = await MainActor.run { UIDevice.current.name }

        guard let url = URL(string: "https://\(hostString):\(host.pairingPort)/api/pair") else {
            throw PairingError.invalidHost
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try JSONEncoder().encode(
            PairingRequest(
                deviceId: DeviceIdentity.current(),
                deviceName: deviceName,
                pin: pin,
                protocolVersion: 1
            )
        )

        let delegate = TOFUSessionDelegate(machineID: host.machineID)
        let session = URLSession(
            configuration: .ephemeral,
            delegate: delegate,
            delegateQueue: nil
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PairingError.invalidResponse
        }

        guard http.statusCode == 200 else {
            throw PairingError.http(http.statusCode)
        }

        let result = try JSONDecoder().decode(PairingResult.self, from: data)
        guard result.ok else {
            throw PairingError.rejected(result.message ?? "Pairing rejected")
        }

        return result
    }
}

enum PairingError: LocalizedError {
    case invalidPIN
    case invalidHost
    case invalidResponse
    case http(Int)
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .invalidPIN: return "Enter the 4-digit PIN shown by Satellite."
        case .invalidHost: return "Could not resolve the Satellite host."
        case .invalidResponse: return "Satellite returned an invalid response."
        case .http(let code): return "Satellite pairing failed (HTTP \(code))."
        case .rejected(let message): return message
        }
    }
}
