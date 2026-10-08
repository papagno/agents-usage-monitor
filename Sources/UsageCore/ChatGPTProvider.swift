import Foundation

/// Uses the Codex CLI login (~/.codex/auth.json) to query ChatGPT plan usage limits.
public struct ChatGPTProvider: UsageProvider {
    public let id = "chatgpt"
    public let name = "ChatGPT"
    public let shortName = "G"
    public init() {}

    static let hint = "Run `codex` and log in with ChatGPT to refresh."

    public func fetch() async throws -> ProviderUsage {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        guard let data = FileManager.default.contents(atPath: home + "/auth.json"),
              let tokens = (try? jsonObject(data))?["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String else {
            throw UsageError.notLoggedIn(Self.hint)
        }
        var headers = ["Authorization": "Bearer \(token)", "User-Agent": "codex-cli"]
        if let account = tokens["account_id"] as? String { headers["ChatGPT-Account-Id"] = account }
        let body = try await HTTP.getJSON(
            URL(string: "https://chatgpt.com/backend-api/wham/usage")!, headers: headers, expiredHint: Self.hint)
        return try Self.parse(body)
    }

    static func label(forWindowSeconds s: Double?, fallback: String) -> String {
        guard let s else { return fallback }
        switch s {
        case ..<(6 * 3600): return "Session (\(Int((s / 3600).rounded()))h)"
        case ..<(8 * 86400): return "Weekly"
        default: return "Monthly"
        }
    }

    public static func parse(_ data: Data) throws -> ProviderUsage {
        let obj = try jsonObject(data)
        guard let rl = obj["rate_limit"] as? [String: Any] else { throw UsageError.parse("missing rate_limit") }
        var windows: [UsageWindow] = []
        for (key, fallback) in [("primary_window", "Primary"), ("secondary_window", "Secondary")] {
            guard let w = rl[key] as? [String: Any], let used = number(w["used_percent"]) else { continue }
            let reset = number(w["reset_at"]).map { Date(timeIntervalSince1970: $0) }
            let seconds = number(w["limit_window_seconds"])
            windows.append(UsageWindow(
                label: label(forWindowSeconds: seconds, fallback: fallback),
                usedPercent: used, resetsAt: reset, duration: seconds))
        }
        if windows.isEmpty { throw UsageError.parse("no usage windows") }
        return ProviderUsage(plan: (obj["plan_type"] as? String)?.capitalized, windows: windows)
    }
}
