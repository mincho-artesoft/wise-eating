import Foundation
import Network

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isConnected: Bool = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = (path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }

    /// Ръчна проверка (полезна при връщане от Settings/Control Center)
    func refreshNow() {
        // NWPathMonitor държи текущ статус; задействаме UI чрез повторна публикация
        isConnected.toggle()
        isConnected.toggle()
    }
}
