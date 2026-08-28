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
    private let deviceIDKey = "dish.deviceId"

    func pair(host: SatelliteHost, pin: String) async throws -> PairingResult {
        guard pin.count == 4, pin.allSatisfy(\.isNumber) else {
            throw PairingError.invalidPIN
        }

        let resolved = try await resolve(host.endpoint)
        let hostString = resolved.host.contains(":") ? "[\(resolved.host)]" : resolved.host

        guard let url = URL(string: "https://\(hostString):\(host.pairingPort)/api/pair") else {
            throw PairingError.invalidHost
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try JSONEncoder().encode(
            PairingRequest(
                deviceId: stableDeviceID(),
                deviceName: UIDevice.current.name,
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

    private func stableDeviceID() -> String {
        if let existing = UserDefaults.standard.string(forKey: deviceIDKey) {
            return existing
        }

        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: deviceIDKey)
        return id
    }

    private func resolve(_ endpoint: NWEndpoint) async throws -> (host: String, port: UInt16) {
        guard case let .service(name, type, domain, interface) = endpoint else {
            throw PairingError.invalidHost
        }

        return try await withCheckedThrowingContinuation { continuation in
            let serviceEndpoint = NWEndpoint.service(
                name: name,
                type: type,
                domain: domain,
                interface: interface
            )
            let connection = NWConnection(to: serviceEndpoint, using: .udp)
            var didResume = false

            func finish(_ result: Result<(host: String, port: UInt16), Error>) {
                guard !didResume else { return }
                didResume = true
                connection.cancel()
                continuation.resume(with: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let remote = connection.currentPath?.remoteEndpoint,
                          case let .hostPort(host, port) = remote else {
                        finish(.failure(PairingError.invalidHost))
                        return
                    }
                    finish(.success((host.debugDescription, port.rawValue)))

                case .failed(let error):
                    finish(.failure(error))

                case .cancelled:
                    if !didResume {
                        finish(.failure(PairingError.invalidHost))
                    }

                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))
        }
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
