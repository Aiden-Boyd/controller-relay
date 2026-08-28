import Foundation
import GameController

@MainActor
final class ControllerManager: ObservableObject {
    @Published private(set) var controllers: [GCController] = []

    init() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }

        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }

        GCController.startWirelessControllerDiscovery { [weak self] in
            Task { @MainActor in self?.refresh() }
        }

        refresh()
    }

    func refresh() {
        controllers = GCController.controllers()
    }
}
