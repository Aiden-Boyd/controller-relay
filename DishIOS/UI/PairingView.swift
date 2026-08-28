import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    let host: SatelliteHost
    @State private var satellitePIN = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(host.name, systemImage: "desktopcomputer")
                }

                Section("Approve on Satellite") {
                    VStack(spacing: 12) {
                        Text("Enter this PIN on the Satellite PC")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(app.clientPairingPIN.isEmpty ? "••••" : app.clientPairingPIN)
                            .font(.system(size: 42, weight: .bold, design: .monospaced))
                            .tracking(8)
                            .frame(maxWidth: .infinity)

                        if app.pairingState == .requestingApproval || app.pairingState == .awaitingApproval {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(
                                    app.pairingState == .requestingApproval
                                        ? "Sending pairing request…"
                                        : "Waiting for approval on Satellite…"
                                )
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 6)

                    Text("Dish sends this request automatically. Approve the matching 4-digit PIN on your Windows PC.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Or use Satellite's PIN") {
                    TextField("4-digit PIN", text: $satellitePIN)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .onChange(of: satellitePIN) { _, value in
                            satellitePIN = String(value.filter(\.isNumber).prefix(4))
                        }

                    Text("If Satellite is already showing a PIN, enter that PIN here instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        Task {
                            await app.pairWithSatellitePIN(host: host, pin: satellitePIN)
                        }
                    } label: {
                        if app.pairingState == .pairingWithSatellitePIN {
                            HStack {
                                ProgressView()
                                Text("Pairing…")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text("Pair with Satellite PIN")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(satellitePIN.count != 4 || app.pairingState == .pairingWithSatellitePIN)
                }

                if let error = app.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Pair with Satellite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        app.cancelPairing()
                        dismiss()
                    }
                }
            }
            .task {
                app.beginPairing(host: host)
            }
            .onChange(of: app.pairingState) { _, state in
                if state == .paired {
                    dismiss()
                }
            }
            .onDisappear {
                if app.pairingState != .paired {
                    app.cancelPairing()
                }
            }
        }
    }
}
