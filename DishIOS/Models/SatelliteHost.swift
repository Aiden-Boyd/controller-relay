import Foundation
import Network

struct SatelliteHost: Identifiable, Hashable {
    let machineID: String
    let name: String
    let endpoint: NWEndpoint
    let pairingPort: UInt16

    var id: String { machineID }
}
