import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if let host = app.selectedSatellite, app.pairingState == .paired {
                    DashboardView(host: host)
                } else {
                    SatelliteListView()
                }
            }
        }
        .task {
            app.discovery.start()
        }
    }
}
