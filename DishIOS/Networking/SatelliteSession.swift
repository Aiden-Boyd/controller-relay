import Foundation
import Network
import UIKit

struct SatelliteSessionDescriptor {
    let connectionID: String
    let tokenHex: String
    let sessionSaltHex: String
    let epoch: UInt16
    let maxControllers: Int
    let registeredControllerIndices: Set<Int>
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

    struct HostFeatures: Encodable {
        let mouseControl: Bool
    }

    let deviceId: String
    let deviceName: String
    let protocolVersion: Int
    let controllers: [Controller]
    let hostFeatures: HostFeatures
}

private struct ConnectionResponse: Decodable {
    struct ControllerApply: Decodable {
        let ctrlIdx: Int
        let result: String
        let appliedType: Int?

        var slotIsLive: Bool {
            result == "ok" || result == "replugFailed"
        }
    }

    let connectionId: String?
    let token: String?
    let sessionSalt: String?
    let epoch: Int?
    let maxControllers: Int?
    let protocolVersion: Int?
    let controllers: [ControllerApply]?
    let error: String?
    let code: String?
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
        let deviceName = await MainActor.run { UIDevice.current.name }

        guard let url = URL(string: "https://\(hostString):\(host.httpPort)/api/connections") else {
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
            deviceName: deviceName,
            protocolVersion: 1,
            controllers: controllers,
            hostFeatures: .init(mouseControl: false)
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

        if http.statusCode == 409 {
            throw SatelliteSessionError.protocolMismatch
        }

        let decoded = try? JSONDecoder().decode(ConnectionResponse.self, from: data)

        if http.statusCode == 401 || decoded?.code == "NOT_PAIRED" || decoded?.code == "BAD_PROOF" {
            throw SatelliteSessionError.repairNeeded
        }

        guard http.statusCode == 200, let decoded else {
            throw SatelliteSessionError.http(http.statusCode)
        }

        guard let connectionID = decoded.connectionId,
              let token = decoded.token,
              token.count == 8,
              let salt = decoded.sessionSalt,
              salt.count == 16 else {
            throw SatelliteSessionError.rejected(decoded.error ?? "Satellite returned incomplete session credentials.")
        }

        let applyResults = decoded.controllers ?? []
        let registered = Set(
            applyResults
                .filter(\.slotIsLive)
                .map(\.ctrlIdx)
        )

        if controllerCount > 0 && registered.isEmpty {
            let detail = applyResults.isEmpty
                ? "Satellite returned no controller apply results."
                : applyResults
                    .map { "#\($0.ctrlIdx): \($0.result)" }
                    .joined(separator: ", ")
            throw SatelliteSessionError.rejected(
                "Satellite did not register the connected controller. \(detail)"
            )
        }

        return SatelliteSessionDescriptor(
            connectionID: connectionID,
            tokenHex: token,
            sessionSaltHex: salt,
            epoch: UInt16(clamping: decoded.epoch ?? 0),
            maxControllers: decoded.maxControllers ?? 16,
            registeredControllerIndices: registered
        )
    }
}

enum SatelliteSessionError: LocalizedError {
    case invalidHost
    case invalidResponse
    case protocolMismatch
    case repairNeeded
    case rejected(String)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "Could not resolve Satellite."
        case .invalidResponse:
            return "Satellite returned an invalid session response."
        case .protocolMismatch:
            return "Dish and Satellite speak different protocol versions. Update both and try again."
        case .repairNeeded:
            return "Satellite no longer recognizes this iPhone. Pair it again."
        case .rejected(let message):
            return message
        case .http(let code):
            return "Satellite session failed (HTTP \(code))."
        }
    }
}
