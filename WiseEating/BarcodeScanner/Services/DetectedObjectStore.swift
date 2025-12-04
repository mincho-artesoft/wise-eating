import Foundation

public actor DetectedObjectStore {
    public static let shared = DetectedObjectStore()

    private var recentItems: [DetectedObjectEntity] = []
    private var pendingLabelsQuery: [String] = []

    public func add(_ items: [DetectedObjectEntity]) {
        guard !items.isEmpty else { return }
        recentItems.insert(contentsOf: items, at: 0)
        if recentItems.count > 300 {
            recentItems.removeLast(recentItems.count - 300)
        }
    }

    public func all() -> [DetectedObjectEntity] { recentItems }

    public func recent(limit: Int) -> [DetectedObjectEntity] {
        Array(recentItems.prefix(max(0, limit)))
    }

    public func search(byAnyLabel labels: [String]) -> [DetectedObjectEntity] {
        let lower = Set(labels.map { $0.lowercased() })
        return recentItems.filter { item in
            if lower.contains(item.title.lowercased()) { return true }
            if let cat = item.category, lower.contains(cat.lowercased()) { return true }
            return false
        }
    }

    public func setPendingQuery(labels: [String]) { pendingLabelsQuery = labels }
    public func pendingQuery() -> [String] { pendingLabelsQuery }
}
