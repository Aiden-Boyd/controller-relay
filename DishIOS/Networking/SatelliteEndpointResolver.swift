import Foundation
import Network
import Darwin

enum SatelliteEndpointResolver {
    @MainActor
    static func resolve(_ endpoint: NWEndpoint) async throws -> (host: String, port: UInt16) {
        guard case let .service(name, type, domain, _) = endpoint else {
            throw PairingError.invalidHost
        }

        let bonjourType = type.hasSuffix(".") ? type : type + "."
        let bonjourDomain: String
        if domain.isEmpty {
            bonjourDomain = "local."
        } else {
            bonjourDomain = domain.hasSuffix(".") ? domain : domain + "."
        }

        return try await withCheckedThrowingContinuation { continuation in
            let operation = BonjourResolverOperation(
                name: name,
                type: bonjourType,
                domain: bonjourDomain,
                continuation: continuation
            )
            operation.start()
        }
    }
}

@MainActor
private final class BonjourResolverOperation: NSObject, NetServiceDelegate {
    private let service: NetService
    private var continuation: CheckedContinuation<(host: String, port: UInt16), Error>?
    private var keepAlive: BonjourResolverOperation?

    init(
        name: String,
        type: String,
        domain: String,
        continuation: CheckedContinuation<(host: String, port: UInt16), Error>
    ) {
        self.service = NetService(domain: domain, type: type, name: name)
        self.continuation = continuation
        super.init()
        self.service.delegate = self
    }

    func start() {
        keepAlive = self
        service.resolve(withTimeout: 8)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let addresses = sender.addresses, !addresses.isEmpty else {
            finish(.failure(PairingError.invalidHost))
            return
        }

        let ipv4 = addresses.first { family(of: $0) == AF_INET }
        let ipv6 = addresses.first { family(of: $0) == AF_INET6 }

        guard let address = ipv4 ?? ipv6,
              let host = numericHost(from: address),
              sender.port > 0,
              sender.port <= Int(UInt16.max) else {
            finish(.failure(PairingError.invalidHost))
            return
        }

        finish(.success((host, UInt16(sender.port))))
    }

    func netService(
        _ sender: NetService,
        didNotResolve errorDict: [String : NSNumber]
    ) {
        finish(.failure(PairingError.invalidHost))
    }

    private func family(of data: Data) -> Int32? {
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return nil }
            return Int32(base.assumingMemoryBound(to: sockaddr.self).pointee.sa_family)
        }
    }

    private func numericHost(from data: Data) -> String? {
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return nil }

            let address = base.assumingMemoryBound(to: sockaddr.self)
            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))

            let result = getnameinfo(
                address,
                socklen_t(data.count),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            guard result == 0 else { return nil }
            return String(cString: hostBuffer)
        }
    }

    private func finish(
        _ result: Result<(host: String, port: UInt16), Error>
    ) {
        guard let continuation else { return }
        self.continuation = nil
        service.stop()
        service.delegate = nil
        continuation.resume(with: result)
        keepAlive = nil
    }
}
