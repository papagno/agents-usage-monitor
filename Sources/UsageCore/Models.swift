import Foundation

public struct UsageWindow: Sendable, Equatable, Identifiable, Codable {
    public var id: String { label }
    public let label: String
    /// 0...100
    public let usedPercent: Double
    public let resetsAt: Date?
    public let detail: String?
    /// Length of the limit window, used to compute the even-pace target.
    public let duration: TimeInterval?

    public init(label: String, usedPercent: Double, resetsAt: Date?, duration: TimeInterval? = nil, detail: String? = nil) {
        self.label = label
        self.usedPercent = max(0, usedPercent)
        self.resetsAt = resetsAt
        self.duration = duration
        self.detail = detail
    }

    /// Usage you'd be at by `now` if consumption were spread evenly over the window (0...100).
    public func expectedPercent(at now: Date = Date()) -> Double? {
        guard let resetsAt, let duration, duration > 0 else { return nil }
        let elapsed = duration - resetsAt.timeIntervalSince(now)
        return min(max(elapsed / duration, 0), 1) * 100
    }
}

public struct ProviderUsage: Sendable, Equatable, Codable {
    public let plan: String?
    public let windows: [UsageWindow]

    public init(plan: String?, windows: [UsageWindow]) {
        self.plan = plan
        self.windows = windows
    }

    /// Whether data fetched at `fetchedAt` still reflects reality: recent enough, and no limit has reset since.
    public func isStillRelevant(fetchedAt: Date, maxAge: TimeInterval, now: Date = Date()) -> Bool {
        guard now.timeIntervalSince(fetchedAt) < maxAge else { return false }
        return !windows.contains { w in w.resetsAt.map { $0 <= now } ?? false }
    }

    /// The most constrained window; what the menu bar shows.
    public var headlinePercent: Double? { windows.map(\.usedPercent).max() }

    /// Values shown in the menu bar: `[session, weekly]` when the plan has both a short session
    /// window and weekly limits (highest weekly wins), otherwise just the headline.
    public var menuBarPercents: [Double] {
        let session = windows.filter { ($0.duration ?? 0) > 0 && $0.duration! <= 6 * 3600 }
        let weekly = windows.filter { ($0.duration ?? 0) > 6 * 3600 && $0.duration! <= 8 * 86400 }
        if let s = session.map(\.usedPercent).max(), let w = weekly.map(\.usedPercent).max() {
            return [s, w]
        }
        return headlinePercent.map { [$0] } ?? []
    }
}

public enum UsageError: LocalizedError, Sendable {
    case notLoggedIn(String)
    case tokenExpired(String)
    case http(Int, String)
    /// `retryAfter` comes from the `Retry-After` header, in seconds from when the response was received.
    case rateLimited(retryAfter: TimeInterval?)
    case parse(String)

    public var isRateLimited: Bool {
        if case .rateLimited = self { true } else { false }
    }

    public var retryAfter: TimeInterval? {
        if case .rateLimited(let s) = self { s } else { nil }
    }

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn(let hint): "Not logged in. \(hint)"
        case .tokenExpired(let hint): "Token expired. \(hint)"
        case .http(let code, let body): "HTTP \(code): \(body.prefix(120))"
        case .rateLimited: "Rate limited by API."
        case .parse(let what): "Unexpected response: \(what)"
        }
    }
}

public protocol UsageProvider: Sendable {
    var id: String { get }
    var name: String { get }
    /// Short tag used in the menu bar title.
    var shortName: String { get }
    func fetch() async throws -> ProviderUsage
}
