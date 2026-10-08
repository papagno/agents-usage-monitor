import Foundation

/// Reads the Claude Code OAuth token from the macOS keychain and queries the subscription usage endpoint.
public struct ClaudeProvider: UsageProvider {
    public let id = "claude"
    public let name = "Claude"
    public let shortName = "C"
    public init() {}

    static let hint = "Run `claude` and log in to refresh."

    public func fetch() async throws -> ProviderUsage {
        let raw: String
        do {
            // Use the `security` CLI: Claude Code writes the item with it, so no keychain prompt is shown.
            raw = try await Shell.run("security", ["find-generic-password", "-s", "Claude Code-credentials", "-w"])
        } catch {
            throw UsageError.notLoggedIn(Self.hint)
        }
        let creds = try jsonObject(Data(raw.utf8))
        guard let oauth = creds["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            throw UsageError.notLoggedIn(Self.hint)
        }
        if let exp = number(oauth["expiresAt"]), Date(timeIntervalSince1970: exp / 1000) < Date() {
            throw UsageError.tokenExpired(Self.hint)
        }
        // The endpoint rate-limits requests that don't identify as Claude Code.
        let version = (try? await Shell.run("claude", ["--version"]))?.split(separator: " ").first.map(String.init) ?? "2.1.0"
        let data = try await HTTP.getJSON(
            URL(string: "https://api.anthropic.com/api/oauth/usage")!,
            headers: ["Authorization": "Bearer \(token)", "anthropic-beta": "oauth-2025-04-20",
                      "User-Agent": "claude-code/\(version)"],
            expiredHint: Self.hint)
        return try Self.parse(data, plan: oauth["subscriptionType"] as? String)
    }

    static let knownWindows: [(key: String, label: String, duration: TimeInterval)] = [
        ("five_hour", "Session (5h)", 5 * 3600),
        ("seven_day", "Weekly", 7 * 86400),
        ("seven_day_sonnet", "Weekly Sonnet", 7 * 86400),
        ("seven_day_opus", "Weekly Opus", 7 * 86400),
    ]

    public static func parse(_ data: Data, plan: String?) throws -> ProviderUsage {
        let obj = try jsonObject(data)
        var windows: [UsageWindow] = []
        for (key, label, duration) in knownWindows {
            guard let w = obj[key] as? [String: Any], let u = number(w["utilization"]) else { continue }
            windows.append(UsageWindow(label: label, usedPercent: u,
                                       resetsAt: parseISODate(w["resets_at"] as? String), duration: duration))
        }
        if let extra = obj["extra_usage"] as? [String: Any],
           extra["is_enabled"] as? Bool == true,
           let u = number(extra["utilization"]) {
            var detail: String?
            if let used = number(extra["used_credits"]), let limit = number(extra["monthly_limit"]) {
                detail = String(format: "$%.2f / $%.2f", used / 100, limit / 100)
            }
            windows.append(UsageWindow(label: "Extra usage", usedPercent: u, resetsAt: nil, detail: detail))
        }
        if windows.isEmpty { throw UsageError.parse("no usage windows") }
        return ProviderUsage(plan: plan?.capitalized, windows: windows)
    }
}
