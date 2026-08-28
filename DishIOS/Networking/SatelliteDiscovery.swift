import Foundation
import Network

@MainActor
final class SatelliteDiscovery: ObservableObject {
    @Published private(set) var hosts: [SatelliteHost] = []
    @Published private(set) var isSearching = false

    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }

        let parameters = NWParameters.udp
        parameters.includePeerToPeer = true

        let descriptor = NWBrowser.Descriptor.bonjour(
            type: "_satellite._udp",
            domain: nil
        )

        let browser = NWBrowser(for: descriptor, using: parameters)
        self.browser = browser
        isSearching = true

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                if case .failed = state {
                    self.stop()
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.hosts = results.compactMap(Self.host(from:))
            }
        }

        browser.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }

    private static func host(from result: NWBrowser.Result) -> SatelliteHost? {
        guard case let .service(name, _, _, _) = result.endpoint else {
            return nil
        }

        var machineID = name
        var pairingPort: UInt16 = 9443
        var httpPort: UInt16 = 9443
        var udpPort: UInt16 = 9876

        if case let .bonjour(txtRecord) = result.metadata {
            if let mid = txtRecord["mid"], !mid.isEmpty {
                machineID = mid
            }

            if let value = txtRecord["pair"], let parsed = UInt16(value) {
                pairingPort = parsed
            }

            if let value = txtRecord["http"], let parsed = UInt16(value) {
                httpPort = parsed
            }

            if let value = txtRecord["udp"], let parsed = UInt16(value) {
                udpPort = parsed
            }
        }

        return SatelliteHost(
            machineID: machineID,
            name: name,
            endpoint: result.endpoint,
            pairingPort: pairingPort,
            httpPort: httpPort,
            udpPort: udpPort
        )
    }
}
