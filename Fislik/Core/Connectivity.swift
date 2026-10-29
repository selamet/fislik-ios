import Network
import Observation

/// Reachability via NWPathMonitor.
@MainActor
@Observable
final class Connectivity {
    static let shared = Connectivity()

    private(set) var isOnline = true
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var listeners: [() -> Void] = []

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let cameOnline = online && !self.isOnline
                self.isOnline = online
                if cameOnline { self.listeners.forEach { $0() } }
            }
        }
        monitor.start(queue: DispatchQueue(label: "dev.selamet.fislik.connectivity"))
    }

    /// Called every time the device goes from offline to online.
    func onReconnect(_ handler: @escaping () -> Void) {
        listeners.append(handler)
    }
}
