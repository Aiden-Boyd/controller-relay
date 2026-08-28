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
                    Label("Paired", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Section("Controllers") {
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
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }

            Section {
                Text("UDP streaming is the next milestone. Discovery, physical-controller detection, TOFU TLS pairing, and secure key storage are scaffolded.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Controller Relay")
    }
}
