import Foundation
import GameController
import Network
import CryptoKit

@MainActor
final class SatelliteStreamer: ObservableObject {
    @Published private(set) var isStreaming = false
    @Published private(set) var lastHeartbeatAck: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var serverEpoch: UInt16?
    @Published private(set) var activeControllerBitmap: UInt16?

    private var connection: NWConnection?
    private var heartbeatTimer: DispatchSourceTimer?
    private var codec: SatelliteUDPPacketCodec?
    private var sendCounter: UInt32 = 1
    private var receiveCounter: UInt32 = 0
    private var activeControllers: [GCController] = []
    private var lastReports: [Int: GamepadReport] = [:]

    func start(
        host: SatelliteHost,
        descriptor: SatelliteSessionDescriptor,
        pairingKeyHex: String,
        controllers: [GCController]
    ) async throws {
        stop()

        activeControllers = Array(controllers.prefix(descriptor.maxControllers))

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

        guard let udpPort = NWEndpoint.Port(rawValue: host.udpPort) else {
            throw SatelliteStreamerError.invalidPort
        }

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(resolved.host),
            port: udpPort
        )

        let connection = NWConnection(to: endpoint, using: .udp)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }

                switch state {
                case .ready:
                    self.isStreaming = true
                    self.installInputHandlers(registered: descriptor.registeredControllerIndices)

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

        let heartbeatTimer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        heartbeatTimer.schedule(deadline: .now(), repeating: .seconds(2))
        heartbeatTimer.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.send(type: .heartbeat, payload: Data())
            }
        }
        heartbeatTimer.resume()
        self.heartbeatTimer = heartbeatTimer
    }

    func stop() {
        for controller in activeControllers {
            controller.extendedGamepad?.valueChangedHandler = nil
        }

        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        connection?.cancel()
        connection = nil
        codec = nil
        activeControllers = []
        lastReports = [:]
        sendCounter = 1
        receiveCounter = 0
        serverEpoch = nil
        activeControllerBitmap = nil
        isStreaming = false
    }

    private func installInputHandlers(registered: Set<Int>) {
        for (index, controller) in activeControllers.enumerated() {
            guard registered.contains(index),
                  let gamepad = controller.extendedGamepad else {
                continue
            }

            sendGamepadIfChanged(index: index, gamepad: gamepad, force: true)

            gamepad.valueChangedHandler = { [weak self] changedGamepad, _ in
                Task { @MainActor in
                    self?.sendGamepadIfChanged(
                        index: index,
                        gamepad: changedGamepad,
                        force: false
                    )
                }
            }
        }
    }

    private func sendGamepadIfChanged(
        index: Int,
        gamepad: GCExtendedGamepad,
        force: Bool
    ) {
        let report = GamepadReport.from(gamepad)

        if !force, lastReports[index] == report {
            return
        }

        lastReports[index] = report

        var payload = Data([UInt8(index)])
        payload.append(report.encode())
        send(type: .input, payload: payload)
    }

    private func send(type: SatelliteMessageType, payload: Data) {
        guard let codec, let connection else { return }

        do {
            if sendCounter >= 0xF0000000 {
                errorMessage = "Session counter is nearing exhaustion. Reconnect to Satellite."
                stop()
                return
            }

            let packet = try codec.seal(
                counter: sendCounter,
                direction: 0x00,
                type: type,
                payload: payload
            )

            sendCounter += 1
            connection.send(content: packet, completion: .contentProcessed { _ in })
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func receiveLoop() {
        guard let connection else { return }

        connection.receiveMessage { [weak self] data, _, _, error in
            Task { @MainActor in
                guard let self else { return }

                if let data {
                    self.handleIncoming(data)
                }

                if error == nil, self.connection != nil {
                    self.receiveLoop()
                }
            }
        }
    }

    private func handleIncoming(_ packet: Data) {
        guard let codec else { return }

        do {
            let decoded = try codec.open(packet, direction: 0x01)

            if receiveCounter != 0, decoded.counter <= receiveCounter {
                return
            }

            receiveCounter = decoded.counter

            switch SatelliteMessageType(rawValue: decoded.type) {
            case .heartbeatAck:
                lastHeartbeatAck = Date()

                if decoded.payload.count >= 6 {
                    serverEpoch = decoded.payload.readBEUInt16(at: 2)
                    activeControllerBitmap = decoded.payload.readBEUInt16(at: 4)
                }

            case .sessionClose:
                errorMessage = "Satellite closed the session."
                stop()

            default:
                break
            }
        } catch {
            // Wrong-token, malformed, replayed, and unauthenticated packets are ignored.
        }
    }
}

enum SatelliteStreamerError: LocalizedError {
    case invalidToken
    case invalidPort

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "Satellite returned an invalid session token."
        case .invalidPort:
            return "Satellite advertised an invalid UDP port."
        }
    }
}
