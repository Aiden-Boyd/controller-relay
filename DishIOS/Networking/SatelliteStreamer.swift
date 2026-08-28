import Foundation
import GameController
import Network
import CryptoKit

@MainActor
final class SatelliteStreamer: ObservableObject {
    @Published private(set) var isStreaming = false
    @Published private(set) var lastHeartbeatAck: Date?
    @Published private(set) var errorMessage: String?

    private var connection: NWConnection?
    private var inputTimer: DispatchSourceTimer?
    private var heartbeatTimer: DispatchSourceTimer?
    private var codec: SatelliteUDPPacketCodec?
    private var sendCounter: UInt32 = 1
    private var receiveCounter: UInt32 = 0

    func start(
        host: SatelliteHost,
        descriptor: SatelliteSessionDescriptor,
        pairingKeyHex: String,
        controllers: [GCController]
    ) async throws {
        stop()

        let resolved = try await SatelliteEndpointResolver.resolve(host.endpoint)
        let key = try HKDFSessionKey.derive(
            pairingKeyHex: pairingKeyHex,
            sessionSaltHex: descriptor.sessionSaltHex,
            tokenHex: descriptor.tokenHex
        )

        guard let token = UInt32(descriptor.tokenHex, radix: 16) else {
            throw SatelliteStreamerError.invalidToken
        }

        codec = SatelliteUDPPacketCodec(token: token, key: key)

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(resolved.host),
            port: NWEndpoint.Port(rawValue: 9876)!
        )

        let connection = NWConnection(to: endpoint, using: .udp)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isStreaming = true
                case .failed(let error):
                    self.errorMessage = error.localizedDescription
                    self.isStreaming = false
                case .cancelled:
                    self.isStreaming = false
                default:
                    break
                }
            }
        }

        connection.start(queue: .global(qos: .userInteractive))
        receiveLoop()

        let inputTimer = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        inputTimer.schedule(deadline: .now(), repeating: .milliseconds(4), leeway: .milliseconds(1))
        inputTimer.setEventHandler { [weak self] in
            self?.sendControllerSnapshots(controllers)
        }
        inputTimer.resume()
        self.inputTimer = inputTimer

        let heartbeatTimer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        heartbeatTimer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(2))
        heartbeatTimer.setEventHandler { [weak self] in
            self?.send(type: .heartbeat, payload: Data())
        }
        heartbeatTimer.resume()
        self.heartbeatTimer = heartbeatTimer
    }

    func stop() {
        inputTimer?.cancel()
        inputTimer = nil
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        connection?.cancel()
        connection = nil
        codec = nil
        sendCounter = 1
        receiveCounter = 0
        isStreaming = false
    }

    private func sendControllerSnapshots(_ controllers: [GCController]) {
        for (index, controller) in controllers.prefix(16).enumerated() {
            guard let gamepad = controller.extendedGamepad else { continue }
            var payload = Data([UInt8(index)])
            payload.append(GamepadReport.from(gamepad).encode())
            send(type: .input, payload: payload)
        }
    }

    private func send(type: SatelliteMessageType, payload: Data) {
        guard let codec, let connection else { return }

        do {
            let packet = try codec.seal(
                counter: sendCounter,
                direction: 0x00,
                type: type,
                payload: payload
            )
            sendCounter &+= 1
            connection.send(content: packet, completion: .contentProcessed { _ in })
        } catch {
            Task { @MainActor in self.errorMessage = error.localizedDescription }
        }
    }

    private func receiveLoop() {
        guard let connection else { return }

        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }

            if let data {
                self.handleIncoming(data)
            }

            if error == nil {
                self.receiveLoop()
            }
        }
    }

    private func handleIncoming(_ packet: Data) {
        guard let codec else { return }

        do {
            let decoded = try codec.open(packet, direction: 0x01)
            guard decoded.counter > receiveCounter else { return }
            receiveCounter = decoded.counter

            switch SatelliteMessageType(rawValue: decoded.type) {
            case .heartbeatAck:
                Task { @MainActor in self.lastHeartbeatAck = Date() }
            case .sessionClose:
                Task { @MainActor in
                    self.errorMessage = "Satellite closed the session."
                    self.stop()
                }
            default:
                break
            }
        } catch {
            // Ignore malformed/unauthenticated packets.
        }
    }
}

enum SatelliteStreamerError: LocalizedError {
    case invalidToken

    var errorDescription: String? {
        "Satellite returned an invalid session token."
    }
}
