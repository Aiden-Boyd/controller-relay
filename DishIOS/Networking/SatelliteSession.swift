import Foundation
import CryptoKit
import Network
import UIKit

struct SatelliteSessionDescriptor {
    let connectionID: String
    let tokenHex: String
    let sessionSaltHex: String
    let epoch: UInt16
    let maxControllers: Int
}

private struct ConnectionRequest: Encodable {
    struct Controller: Encodable {
        struct Caps: Encodable {
            let rumble: Bool
            let motion: Bool
            let analogTriggers: Bool
            let lightbar: Bool
        }

        let ctrlIdx: Int
        let type: Int
        let caps: Caps
        let touchpadMode: String
    }

    let deviceId: String
    let deviceName: String
    let protocolVersion: Int
    let hmacProof: String
    let controllers: [Controller]
}

private struct ConnectionResponse: Decodable {
    let connectionId: String
    let token: String
    let sessionSalt: String
    let epoch: UInt16
    let maxControllers: Int
}

final class SatelliteSessionClient {
    func create(
        host: SatelliteHost,
        deviceID: String,
        pairingKeyHex: String,
        controllerCount: Int
    ) async throws -> SatelliteSessionDescriptor {
        let proof = try HMACProof.make(pairingKeyHex: pairingKeyHex, deviceID: deviceID)
        let resolved = try await SatelliteEndpointResolver.resolve(host.endpoint)
        let hostString = resolved.host.contains(":") ? "[\(resolved.host)]" : resolved.host

        guard let url = URL(string: "https://\(hostString):\(host.pairingPort)/api/connections") else {
            throw SatelliteSessionError.invalidHost
        }

        let controllers = (0..<controllerCount).map { idx in
            ConnectionRequest.Controller(
                ctrlIdx: idx,
                type: 0,
                caps: .init(
                    rumble: true,
                    motion: false,
                    analogTriggers: true,
                    lightbar: false
                ),
                touchpadMode: "off"
            )
        }

        let body = ConnectionRequest(
            deviceId: deviceID,
            deviceName: UIDevice.current.name,
            protocolVersion: 1,
            hmacProof: proof,
            controllers: controllers
        )

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "X-Device-Id")
        request.setValue(proof, forHTTPHeaderField: "X-Hmac-Proof")
        request.httpBody = try JSONEncoder().encode(body)

        let delegate = TOFUSessionDelegate(machineID: host.machineID)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw SatelliteSessionError.invalidResponse
        }

        guard http.statusCode == 200 else {
            throw SatelliteSessionError.http(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(ConnectionResponse.self, from: data)
        return SatelliteSessionDescriptor(
            connectionID: decoded.connectionId,
            tokenHex: decoded.token,
            sessionSaltHex: decoded.sessionSalt,
            epoch: decoded.epoch,
            maxControllers: decoded.maxControllers
        )
    }
}

enum SatelliteSessionError: LocalizedError {
    case invalidHost
    case invalidResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidHost: return "Could not resolve Satellite."
        case .invalidResponse: return "Satellite returned an invalid session response."
        case .http(let code): return "Satellite session failed (HTTP \(code))."
        }
    }
}
