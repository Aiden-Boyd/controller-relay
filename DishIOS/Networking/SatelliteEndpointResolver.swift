import Foundation
import Network

enum SatelliteEndpointResolver {
    static func resolve(_ endpoint: NWEndpoint) async throws -> (host: String, port: UInt16) {
        guard case let .service(name, type, domain, interface) = endpoint else {
            throw PairingError.invalidHost
        }

        return try await withCheckedThrowingContinuation { continuation in
            let service = NWEndpoint.service(name: name, type: type, domain: domain, interface: interface)
            let connection = NWConnection(to: service, using: .udp)
            var finished = false

            func finish(_ result: Result<(host: String, port: UInt16), Error>) {
                guard !finished else { return }
                finished = true
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
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))
        }
    }
}
