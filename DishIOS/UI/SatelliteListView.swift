import SwiftUI

struct SatelliteListView: View {
    @EnvironmentObject private var app: AppModel
    @State private var pairingHost: SatelliteHost?

    var body: some View {
        List {
            Section {
                if app.discovery.hosts.isEmpty {
                    ContentUnavailableView(
                        "Looking for Satellite",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("Make sure your iPhone and gaming PC are on the same network.")
                    )
                } else {
                    ForEach(app.discovery.hosts) { host in
                        Button {
                            Task {
                                let connected = await app.connectIfPaired(host: host)
                                if !connected {
                                    pairingHost = host
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "desktopcomputer")
                                VStack(alignment: .leading) {
                                    Text(host.name)
                                        .font(.headline)
                                    Text(host.machineID)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Satellites")
            }

            Section("Controllers") {
                if app.controllerManager.controllers.isEmpty {
                    Text("No controllers connected")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(app.controllerManager.controllers.enumerated()), id: \.offset) { index, controller in
                        HStack {
                            Image(systemName: "gamecontroller.fill")
                            Text(controller.vendorName ?? "Controller \(index + 1)")
                            Spacer()
                            Text("P\(index + 1)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Dish")
        .sheet(item: $pairingHost) { host in
            PairingView(host: host)
        }
    }
}
