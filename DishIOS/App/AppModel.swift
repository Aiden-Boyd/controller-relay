import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSatellite: SatelliteHost?
    @Published var pairingState: PairingState = .idle
    @Published var errorMessage: String?
    @Published var sessionDescriptor: SatelliteSessionDescriptor?

    let discovery = SatelliteDiscovery()
    let pairing = SatellitePairingClient()
    let sessionClient = SatelliteSessionClient()
    let streamer = SatelliteStreamer()
    let controllerManager = ControllerManager()

    func pair(host: SatelliteHost, pin: String) async {
        pairingState = .pairing
        errorMessage = nil

        do {
            let result = try await pairing.pair(host: host, pin: pin)
            try PairingKeyStore.save(result.sharedKey, machineID: host.machineID)
            selectedSatellite = host
            pairingState = .paired
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

enum PairingState: Equatable {
    case idle
    case pairing
    case paired
    case failed
}

enum AppModelError: LocalizedError {
    case missingPairingKey

    var errorDescription: String? {
        "Pairing key is missing. Pair with Satellite again."
    }
}
