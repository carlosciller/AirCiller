import Foundation
import Network
import Observation

@Observable
@MainActor
final class NetworkMonitor {
    private(set) var isReady = false
    private(set) var summary = "Comprobando red…"
    private(set) var symbol = "network"

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "local.airciller.network-monitor", qos: .utility)

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let ready = path.status == .satisfied
            let result: (String, String)
            if path.usesInterfaceType(.wifi) {
                result = (ready ? "Wi‑Fi preparado" : "Wi‑Fi sin conexión", "wifi")
            } else if path.usesInterfaceType(.wiredEthernet) {
                result = (ready ? "Ethernet preparado" : "Ethernet sin conexión", "cable.connector")
            } else if ready {
                result = ("Red local preparada", "network")
            } else {
                result = ("Sin red local", "wifi.exclamationmark")
            }
            Task { @MainActor [weak self] in
                self?.isReady = ready
                self?.summary = result.0
                self?.symbol = result.1
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
