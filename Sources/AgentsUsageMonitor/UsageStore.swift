import Foundation
import Observation
import UsageCore

enum ProviderState {
    case loading
    case loaded(ProviderUsage, at: Date)
    /// `last`/`at` keep the previous successful result so it can still be shown.
    case failed(String, rateLimited: Bool, last: ProviderUsage?, at: Date?)

    var usage: ProviderUsage? {
        switch self {
        case .loading: nil
        case .loaded(let u, _): u
        case .failed(_, _, let last, _): last
        }
    }

    var updatedAt: Date? {
        switch self {
        case .loading: nil
        case .loaded(_, let at): at
        case .failed(_, _, _, let at): at
        }
    }

    var isRateLimited: Bool {
        if case .failed(_, true, _, _) = self { true } else { false }
    }
}

private struct CachedUsage: Codable {
    let usage: ProviderUsage
    let at: Date
}

@MainActor
@Observable
final class UsageStore {
    let providers: [any UsageProvider] = [ClaudeProvider(), ChatGPTProvider(), CopilotProvider()]
    private(set) var layout: ProviderLayout {
        didSet {
            UserDefaults.standard.set(layout.order, forKey: Self.orderKey)
            UserDefaults.standard.set(Array(layout.hidden), forKey: Self.hiddenKey)
        }
    }
    private(set) var states: [String: ProviderState] = [:]
    /// Per-provider "don't call before" times from `Retry-After`; persisted so restarts obey them too.
    private(set) var retryAt: [String: Date] = [:] {
        didSet {
            UserDefaults.standard.set(retryAt.mapValues(\.timeIntervalSince1970), forKey: Self.retryAtKey)
        }
    }
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false
    private var timer: Timer?

    static let refreshInterval: TimeInterval = 5 * 60
    private static let orderKey = "providerOrder"
    private static let hiddenKey = "hiddenProviders"
    private static let cacheKey = "lastKnownUsage"
    private static let retryAtKey = "retryAt"

    init() {
        let defaults = UserDefaults.standard
        layout = ProviderLayout(knownIDs: providers.map(\.id),
                                savedOrder: defaults.stringArray(forKey: Self.orderKey) ?? [],
                                hidden: defaults.stringArray(forKey: Self.hiddenKey) ?? [])
        // Start from the last known values so they survive restarts (and rate limits right after launch).
        let cache = (defaults.data(forKey: Self.cacheKey))
            .flatMap { try? JSONDecoder().decode([String: CachedUsage].self, from: $0) } ?? [:]
        let now = Date()
        let savedRetry = (defaults.dictionary(forKey: Self.retryAtKey) as? [String: Double]) ?? [:]
        retryAt = savedRetry.mapValues(Date.init(timeIntervalSince1970:)).filter { $0.value > now }
        for p in providers {
            let cached = cache[p.id]
            if retryAt[p.id] != nil {
                states[p.id] = .failed(UsageError.rateLimited(retryAfter: nil).localizedDescription,
                                       rateLimited: true, last: cached?.usage, at: cached?.at)
            } else {
                states[p.id] = cached.map { .loaded($0.usage, at: $0.at) } ?? .loading
            }
        }
        lastRefresh = cache.values.map(\.at).max()
        // Skip providers whose saved values are still relevant; the timer picks them up later.
        Task { await refresh(onlyStale: true) }
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh(onlyStale: Bool = false) async {
        guard !isRefreshing else { return }
        let targets = visibleProviders.filter { !onlyStale || needsFetch($0.id) }
        guard !targets.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false; lastRefresh = Date() }
        await withTaskGroup(of: Void.self) { group in
            for p in targets {
                group.addTask { await self.fetch(p) }
            }
        }
    }

    private func needsFetch(_ id: String) -> Bool {
        guard let state = states[id], let usage = state.usage, let at = state.updatedAt else { return true }
        return !usage.isStillRelevant(fetchedAt: at, maxAge: Self.refreshInterval)
    }

    private func fetch(_ p: any UsageProvider) async {
        if let until = retryAt[p.id], until > Date() { return }
        do {
            states[p.id] = .loaded(try await p.fetch(), at: Date())
            retryAt[p.id] = nil
            saveCache()
        } catch {
            let usageError = error as? UsageError
            if let delay = usageError?.retryAfter, delay > 0 {
                retryAt[p.id] = Date().addingTimeInterval(delay)
            }
            let previous = states[p.id]
            states[p.id] = .failed(error.localizedDescription,
                                   rateLimited: usageError?.isRateLimited ?? false,
                                   last: previous?.usage, at: previous?.updatedAt)
        }
    }

    private func saveCache() {
        var cache: [String: CachedUsage] = [:]
        for (id, state) in states {
            if let usage = state.usage, let at = state.updatedAt { cache[id] = CachedUsage(usage: usage, at: at) }
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(cache), forKey: Self.cacheKey)
    }

    /// Visible providers in the user's order.
    var visibleProviders: [any UsageProvider] {
        layout.visible.compactMap { id in providers.first { $0.id == id } }
    }

    /// All providers in the user's order, for the visibility settings.
    var orderedProviders: [any UsageProvider] {
        layout.order.compactMap { id in providers.first { $0.id == id } }
    }

    func setVisible(_ id: String, _ visible: Bool) {
        layout.setVisible(id, visible)
        // Hidden providers aren't refreshed, so fetch fresh data when one is shown again.
        if visible, let p = providers.first(where: { $0.id == id }) {
            Task { await fetch(p) }
        }
    }

    func move(_ id: String, to target: String) {
        layout.move(id, to: target)
    }

    var menuBarItems: [MenuBarItem] {
        visibleProviders.map { p in
            let values = states[p.id]?.usage?.menuBarPercents ?? []
            return MenuBarItem(id: p.id,
                               percents: values.isEmpty ? ["–"] : values.map { "\(Int($0.rounded()))%" },
                               warning: states[p.id]?.isRateLimited ?? false)
        }
    }
}
