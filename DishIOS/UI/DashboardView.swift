import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var app: AppModel
    let host: SatelliteHost

    var body: some View {
        List {
            Section {
                HStack {
                    Label(host.name, systemImage: "desktopcomputer")
                    Spacer()
                    Label(
                        app.streamer.isStreaming ? "Streaming" : "Paired",
                        systemImage: app.streamer.isStreaming ? "antenna.radiowaves.left.and.right" : "checkmark.circle.fill"
                    )
                    .foregroundStyle(app.streamer.isStreaming ? .green : .secondary)
                }

                if let ack = app.streamer.lastHeartbeatAck {
                    LabeledContent("Last heartbeat", value: ack.formatted(date: .omitted, time: .standard))
                }
            }

            Section("Controllers") {
                LabeledContent(
                    "Detected on iPhone",
                    value: "\(app.controllerManager.controllers.count)"
                )

                LabeledContent(
                    "Registered on Satellite",
                    value: "\(app.sessionDescriptor?.registeredControllerIndices.count ?? 0)"
                )

                if app.controllerManager.controllers.isEmpty {
                    ContentUnavailableView(
                        "No Controllers",
                        systemImage: "gamecontroller",
                        description: Text("Pair an Xbox, PlayStation, or MFi controller with this iPhone.")
                    )
                } else {
                    ForEach(Array(app.controllerManager.controllers.enumerated()), id: \.offset) { index, controller in
                        HStack {
                            Image(systemName: "gamecontroller.fill")
                            VStack(alignment: .leading) {
                                Text(controller.vendorName ?? "Controller \(index + 1)")
                                Text("Player \(index + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if app.streamer.isStreaming {
                                Image(systemName: "wave.3.right.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }

            Section {
                Button(app.streamer.isStreaming ? "Stop Streaming" : "Start Streaming") {
                    if app.streamer.isStreaming {
                        app.stopStreaming()
                    } else {
                        Task { await app.startStreaming() }
                    }
                }
                .disabled(app.controllerManager.controllers.isEmpty && !app.streamer.isStreaming)

                if let error = app.streamer.errorMessage ?? app.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Dish")
        .onDisappear {
            app.stopStreaming()
        }
    }
}
