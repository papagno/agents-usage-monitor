/// User-chosen order and visibility of providers. Always keeps at least one provider visible.
public struct ProviderLayout: Equatable, Sendable {
    public private(set) var order: [String]
    public private(set) var hidden: Set<String>

    /// Reconciles saved preferences with the providers that currently exist: unknown IDs are dropped
    /// and new providers are appended.
    public init(knownIDs: [String], savedOrder: [String] = [], hidden: [String] = []) {
        var seen = Set<String>()
        let saved = savedOrder.filter { knownIDs.contains($0) && seen.insert($0).inserted }
        order = saved + knownIDs.filter { !seen.contains($0) }
        self.hidden = Set(hidden).intersection(knownIDs)
        if self.hidden.count >= order.count, let first = order.first { self.hidden.remove(first) }
    }

    public var visible: [String] { order.filter { !hidden.contains($0) } }

    public func isVisible(_ id: String) -> Bool { !hidden.contains(id) }

    public func canToggle(_ id: String) -> Bool { !isVisible(id) || visible.count > 1 }

    public mutating func setVisible(_ id: String, _ visible: Bool) {
        if visible { hidden.remove(id) } else if canToggle(id) { hidden.insert(id) }
    }

    /// Moves `id` into the position currently held by `target`.
    public mutating func move(_ id: String, to target: String) {
        guard id != target, let from = order.firstIndex(of: id), let to = order.firstIndex(of: target) else { return }
        order.remove(at: from)
        order.insert(id, at: to)
    }
}
