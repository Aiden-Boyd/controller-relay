import SwiftUI

struct SatelliteListView: View {
    @EnvironmentObject private var app: AppModel
    @State private var pairingHost: SatelliteHost?
    @State private var connectingHostID: String?

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
                        VStack(spacing: 0) {
                            Button {
                                Task {
                                    connectingHostID = host.id
                                    let result = await app.prepareConnection(host: host)
                                    connectingHostID = nil

                                    if result == .pairingRequired {
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

                                    if connectingHostID == host.id {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(connectingHostID != nil)

                            Button("Pair / Repair") {
                                pairingHost = host
                            }
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, 6)
                        }
                    }
                }
            } header: {
                Text("Satellites")
            }

            if let error = app.errorMessage, app.pairingState == .failed {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            Section("Controllers") {
                if app.controllerManager.controllers.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No controllers connected")
                            .foregroundStyle(.secondary)
                        Text("If your Xbox controller is connected in iPhone Settings, tap Refresh.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Refresh Controllers") {
                        app.controllerManager.refresh()
                    }
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

                    Button("Refresh Controllers") {
                        app.controllerManager.refresh()
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
