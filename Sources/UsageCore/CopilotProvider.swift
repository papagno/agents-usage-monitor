import Foundation

/// Uses the GitHub CLI token (`gh auth token`) to query Copilot quota snapshots.
public struct CopilotProvider: UsageProvider {
    public let id = "copilot"
    public let name = "Copilot"
    public let shortName = "P"
    public init() {}

    static let hint = "Run `gh auth login` to refresh."

    public func fetch() async throws -> ProviderUsage {
        let token: String
        if let env = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !env.isEmpty {
            token = env
        } else {
            do { token = try await Shell.run("gh", ["auth", "token"]) } catch { throw UsageError.notLoggedIn(Self.hint) }
        }
        let data = try await HTTP.getJSON(
            URL(string: "https://api.github.com/copilot_internal/user")!,
            headers: ["Authorization": "token \(token)", "Accept": "application/json", "Editor-Version": "vscode/1.100.0"],
            expiredHint: Self.hint)
        return try Self.parse(data)
    }

    static let labels = ["premium_interactions": "Premium requests", "chat": "Chat", "completions": "Completions"]

    public static func parse(_ data: Data) throws -> ProviderUsage {
        let obj = try jsonObject(data)
        guard let snaps = obj["quota_snapshots"] as? [String: Any] else { throw UsageError.parse("missing quota_snapshots") }
        let reset = parseISODate(obj["quota_reset_date"] as? String)
        // Quotas reset monthly; the window started one calendar month before the reset date.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let duration = reset.flatMap { r in
            utc.date(byAdding: .month, value: -1, to: r).map { r.timeIntervalSince($0) }
        }
        var windows: [UsageWindow] = []
        for key in snaps.keys.sorted(by: { ($0 == "premium_interactions" ? "" : $0) < ($1 == "premium_interactions" ? "" : $1) }) {
            guard let s = snaps[key] as? [String: Any], s["unlimited"] as? Bool != true,
                  let remaining = number(s["percent_remaining"]) else { continue }
            var detail: String?
            if let ent = number(s["entitlement"]), ent > 0, let rem = number(s["remaining"]) {
                detail = "\(Int(ent - rem)) / \(Int(ent))"
            }
            windows.append(UsageWindow(label: labels[key] ?? key, usedPercent: 100 - remaining, resetsAt: reset,
                                       duration: duration, detail: detail))
        }
        if windows.isEmpty {
            windows.append(UsageWindow(label: "Unlimited", usedPercent: 0, resetsAt: nil))
        }
        return ProviderUsage(plan: (obj["copilot_plan"] as? String)?.capitalized, windows: windows)
    }
}
