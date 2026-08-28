import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    let host: SatelliteHost
    @State private var pin = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(host.name, systemImage: "desktopcomputer")
                }

                Section("Pairing PIN") {
                    TextField("1234", text: $pin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .onChange(of: pin) { _, value in
                            pin = String(value.filter(\.isNumber).prefix(4))
                        }

                    Text("Enter the 4-digit PIN shown by Satellite on your Windows PC.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = app.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                Button {
                    Task {
                        await app.pair(host: host, pin: pin)
                        if app.pairingState == .paired {
                            dismiss()
                        }
                    }
                } label: {
                    if app.pairingState == .pairing {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Pair")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(pin.count != 4 || app.pairingState == .pairing)
            }
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
