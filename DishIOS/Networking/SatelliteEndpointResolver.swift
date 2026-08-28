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
            let state = ResolverState()

            connection.stateUpdateHandler = { nwState in
                switch nwState {
                case .ready:
                    guard let remote = connection.currentPath?.remoteEndpoint,
                          case let .hostPort(host, port) = remote else {
                        state.finish(.failure(PairingError.invalidHost), connection: connection, continuation: continuation)
                        return
                    }

                    state.finish(
                        .success((host.debugDescription, port.rawValue)),
                        connection: connection,
                        continuation: continuation
                    )

                case .failed(let error):
                    state.finish(.failure(error), connection: connection, continuation: continuation)

                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))
        }
    }
}

private final class ResolverState: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func finish(
        _ result: Result<(host: String, port: UInt16), Error>,
        connection: NWConnection,
        continuation: CheckedContinuation<(host: String, port: UInt16), Error>
    ) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()

        connection.cancel()
        continuation.resume(with: result)
    }
}
