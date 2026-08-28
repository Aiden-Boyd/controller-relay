import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSatellite: SatelliteHost?
    @Published var pairingState: PairingState = .idle
    @Published var errorMessage: String?
    @Published var sessionDescriptor: SatelliteSessionDescriptor?
    @Published var clientPairingPIN = ""

    let discovery = SatelliteDiscovery()
    let pairing = SatellitePairingClient()
    let sessionClient = SatelliteSessionClient()
    let streamer = SatelliteStreamer()
    let controllerManager = ControllerManager()

    private var approvalTask: Task<Void, Never>?

    func prepareConnection(host: SatelliteHost) async -> ConnectionPreparation {
        errorMessage = nil

        do {
            if try PairingKeyStore.load(machineID: host.machineID) != nil {
                selectedSatellite = host
                pairingState = .paired
                await startStreaming()
                return .connected
            }

            let probe = try await pairing.probe(host: host)

            if probe.ok, let key = PairingApproval.validSharedKey(probe.sharedKey) {
                try PairingKeyStore.save(key, machineID: host.machineID)
                selectedSatellite = host
                pairingState = .paired
                await startStreaming()
                return .connected
            }

            pairingState = .idle
            return .pairingRequired
        } catch {
            pairingState = .failed
            errorMessage = error.localizedDescription
            return .failed
        }
    }

    func beginPairing(host: SatelliteHost) {
        cancelPairing()
        errorMessage = nil
        clientPairingPIN = PairingApproval.generatePIN()
        pairingState = .requestingApproval

        approvalTask = Task { [weak self] in
            guard let self else { return }

            do {
                let initial = try await self.pairing.requestApproval(
                    host: host,
                    clientPIN: self.clientPairingPIN
                )

                if let key = PairingApproval.validSharedKey(initial.sharedKey), initial.ok {
                    await self.completePairing(host: host, sharedKey: key)
                    return
                }

                self.pairingState = .awaitingApproval

                for _ in 0..<60 {
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: 2_000_000_000)

                    switch try await self.pairing.approvalStatus(host: host) {
                    case .approved(let key):
                        await self.completePairing(host: host, sharedKey: key)
                        return

                    case .pending:
                        continue

                    case .declined:
                        self.pairingState = .failed
                        self.errorMessage = "The Satellite declined the pairing request."
                        self.approvalTask = nil
                        return
                    }
                }

                self.pairingState = .failed
                self.errorMessage = "No response from Satellite. The pairing request timed out."
                self.approvalTask = nil
            } catch is CancellationError {
                return
            } catch {
                self.pairingState = .failed
                self.errorMessage = error.localizedDescription
                self.approvalTask = nil
            }
        }
    }

    func pairWithSatellitePIN(host: SatelliteHost, pin: String) async {
        let priorState = pairingState
        pairingState = .pairingWithSatellitePIN
        errorMessage = nil

        do {
            let result = try await pairing.pairWithSatellitePIN(host: host, pin: pin)
            guard let key = PairingApproval.validSharedKey(result.sharedKey) else {
                throw PairingError.invalidResponse
            }

            await completePairing(host: host, sharedKey: key)
        } catch {
            errorMessage = error.localizedDescription
            if approvalTask != nil {
                pairingState = priorState == .requestingApproval ? .requestingApproval : .awaitingApproval
            } else {
                pairingState = .failed
            }
        }
    }

    func cancelPairing() {
        approvalTask?.cancel()
        approvalTask = nil
        clientPairingPIN = ""
        if pairingState != .paired {
            pairingState = .idle
        }
    }

    private func completePairing(host: SatelliteHost, sharedKey: String) async {
        do {
            try PairingKeyStore.save(sharedKey, machineID: host.machineID)
            approvalTask?.cancel()
            approvalTask = nil
            selectedSatellite = host
            pairingState = .paired
            errorMessage = nil
            await startStreaming()
        } catch {
            pairingState = .failed
            errorMessage = error.localizedDescription
        }
    }

    func startStreaming() async {
        guard let host = selectedSatellite else { return }

        do {
            guard let pairingKey = try PairingKeyStore.load(machineID: host.machineID) else {
                throw AppModelError.missingPairingKey
            }

            let count = min(controllerManager.controllers.count, 16)
            let descriptor = try await sessionClient.create(
                host: host,
                deviceID: DeviceIdentity.current(),
                pairingKeyHex: pairingKey,
                controllerCount: count
            )
            sessionDescriptor = descriptor

            try await streamer.start(
                host: host,
                descriptor: descriptor,
                pairingKeyHex: pairingKey,
                controllers: controllerManager.controllers
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopStreaming() {
        streamer.stop()
        sessionDescriptor = nil
    }
}

enum ConnectionPreparation: Equatable {
    case connected
    case pairingRequired
    case failed
}

enum PairingState: Equatable {
    case idle
    case requestingApproval
    case awaitingApproval
    case pairingWithSatellitePIN
    case paired
    case failed
}

enum AppModelError: LocalizedError {
    case missingPairingKey

    var errorDescription: String? {
        "Pairing key is missing. Pair with Satellite again."
    }
}
