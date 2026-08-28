import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSatellite: SatelliteHost?
    @Published var pairingState: PairingState = .idle
    @Published var errorMessage: String?

    let discovery = SatelliteDiscovery()
    let pairing = SatellitePairingClient()
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
}

enum PairingState {
    case idle
    case pairing
    case paired
    case failed
}
