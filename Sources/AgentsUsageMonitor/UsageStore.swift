import Foundation
import Observation
import UsageCore

enum ProviderState {
    case loading
    case loaded(ProviderUsage, at: Date)
    case failed(String, last: ProviderUsage?)

    var usage: ProviderUsage? {
        switch self {
        case .loading: nil
        case .loaded(let u, _): u
        case .failed(_, let last): last
        }
    }
}

@MainActor
@Observable
final class UsageStore {
    let providers: [any UsageProvider] = [ClaudeProvider(), ChatGPTProvider(), CopilotProvider()]
    private(set) var states: [String: ProviderState] = [:]
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false
    private var timer: Timer?

    static let refreshInterval: TimeInterval = 5 * 60

    init() {
        for p in providers { states[p.id] = .loading }
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false; lastRefresh = Date() }
        await withTaskGroup(of: (String, Result<ProviderUsage, Error>).self) { group in
            for p in providers {
                group.addTask {
                    do { return (p.id, .success(try await p.fetch())) } catch { return (p.id, .failure(error)) }
                }
            }
            for await (id, result) in group {
                switch result {
                case .success(let u): states[id] = .loaded(u, at: Date())
                case .failure(let e): states[id] = .failed(e.localizedDescription, last: states[id]?.usage)
                }
            }
        }
    }

    var menuBarItems: [(id: String, percent: String)] {
        providers.map { p in
            (p.id, states[p.id]?.usage?.headlinePercent.map { "\(Int($0.rounded()))%" } ?? "–")
        }
    }
}
