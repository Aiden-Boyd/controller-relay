import Foundation
import Network
import UIKit

struct PairingResponse: Decodable {
    let ok: Bool
    let pending: Bool?
    let message: String?
    let sharedKey: String?
    let protocolVersion: Int?
    let error: String?
}

private struct PairingRequest: Encodable {
    let deviceId: String
    let deviceName: String
    let pin: String?
    let clientPin: String?
    let protocolVersion: Int
}

private struct PairStatusResponse: Decodable {
    let ok: Bool
    let status: String?
    let sharedKey: String?
}

final class SatellitePairingClient: NSObject {
    func probe(host: SatelliteHost) async throws -> PairingResponse {
        try await sendPairRequest(host: host, pin: "", clientPin: nil)
    }

    func pairWithSatellitePIN(host: SatelliteHost, pin: String) async throws -> PairingResponse {
        guard pin.count == 4, pin.allSatisfy(\.isNumber) else {
            throw PairingError.invalidPIN
        }

        let response = try await sendPairRequest(host: host, pin: pin, clientPin: nil)
        guard response.ok, PairingApproval.validSharedKey(response.sharedKey) != nil else {
            throw PairingError.rejected(response.error ?? response.message ?? "Pairing failed")
        }
        return response
    }

    func requestApproval(host: SatelliteHost, clientPIN: String) async throws -> PairingResponse {
        guard clientPIN.count == 4, clientPIN.allSatisfy(\.isNumber) else {
            throw PairingError.invalidPIN
        }

        return try await sendPairRequest(host: host, pin: nil, clientPin: clientPIN)
    }

    func approvalStatus(host: SatelliteHost) async throws -> PairApprovalStatus {
        let url = try await makeURL(host: host, port: host.httpPort, path: "/api/pair/status?deviceId=\(DeviceIdentity.current())")
        let session = makeSession(host: host)
        let (data, response) = try await session.data(from: url)

        guard let http = response as? HTTPURLResponse else {
            throw PairingError.invalidResponse
        }

        guard http.statusCode == 200 else {
            throw PairingError.http(http.statusCode)
        }

        let status = try JSONDecoder().decode(PairStatusResponse.self, from: data)

        if status.status == "approved", let key = PairingApproval.validSharedKey(status.sharedKey) {
            return .approved(key)
        }

        if status.status == "pending" {
            return .pending
        }

        return .declined
    }

    private func sendPairRequest(
        host: SatelliteHost,
        pin: String?,
        clientPin: String?
    ) async throws -> PairingResponse {
        let url = try await makeURL(host: host, port: host.pairingPort, path: "/api/pair")
        let deviceName = await MainActor.run { UIDevice.current.name }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try JSONEncoder().encode(
            PairingRequest(
                deviceId: DeviceIdentity.current(),
                deviceName: deviceName,
                pin: pin,
                clientPin: clientPin,
                protocolVersion: 1
            )
        )

        let session = makeSession(host: host)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw PairingError.invalidResponse
        }

        if http.statusCode == 409 {
            throw PairingError.protocolMismatch
        }

        guard http.statusCode == 200 else {
            throw PairingError.http(http.statusCode)
        }

        return try JSONDecoder().decode(PairingResponse.self, from: data)
    }

    private func makeURL(host: SatelliteHost, port: UInt16, path: String) async throws -> URL {
        let resolved = try await SatelliteEndpointResolver.resolve(host.endpoint)
        let hostString = resolved.host.contains(":") ? "[\(resolved.host)]" : resolved.host

        guard let url = URL(string: "https://\(hostString):\(port)\(path)") else {
            throw PairingError.invalidHost
        }

        return url
    }

    private func makeSession(host: SatelliteHost) -> URLSession {
        let delegate = TOFUSessionDelegate(machineID: host.machineID)
        return URLSession(
            configuration: .ephemeral,
            delegate: delegate,
            delegateQueue: nil
        )
    }
}

enum PairingError: LocalizedError {
    case invalidPIN
    case invalidHost
    case invalidResponse
    case http(Int)
    case protocolMismatch
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .invalidPIN:
            return "Enter a 4-digit PIN."
        case .invalidHost:
            return "Could not resolve the Satellite host."
        case .invalidResponse:
            return "Satellite returned an invalid response."
        case .http(let code):
            return "Satellite pairing failed (HTTP \(code))."
        case .protocolMismatch:
            return "Dish and Satellite use different protocol versions. Update both and try again."
        case .rejected(let message):
            return message
        }
    }
}
