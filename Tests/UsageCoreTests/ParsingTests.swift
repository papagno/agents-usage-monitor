import Foundation
import Testing
@testable import UsageCore

@Test func claudeParsesWindowsAndExtraUsage() throws {
    let json = """
    {"five_hour":{"utilization":12.0,"resets_at":"2026-10-08T12:00:00.123+00:00"},
     "seven_day":{"utilization":40,"resets_at":"2026-10-12T00:00:00Z"},
     "seven_day_opus":null,
     "extra_usage":{"is_enabled":true,"monthly_limit":5000,"used_credits":1234,"utilization":24.68}}
    """
    let u = try ClaudeProvider.parse(Data(json.utf8), plan: "max")
    #expect(u.plan == "Max")
    #expect(u.windows.map(\.label) == ["Session (5h)", "Weekly", "Extra usage"])
    #expect(u.windows[0].resetsAt != nil)
    #expect(u.windows[2].detail == "$12.34 / $50.00")
    #expect(u.headlinePercent == 40)
}

@Test func chatgptParsesPrimaryAndSecondary() throws {
    let json = """
    {"plan_type":"plus","rate_limit":{
      "primary_window":{"used_percent":7,"limit_window_seconds":18000,"reset_at":1793622392},
      "secondary_window":{"used_percent":55,"limit_window_seconds":604800,"reset_at":1793622392}}}
    """
    let u = try ChatGPTProvider.parse(Data(json.utf8))
    #expect(u.plan == "Plus")
    #expect(u.windows.map(\.label) == ["Session (5h)", "Weekly"])
    #expect(u.headlinePercent == 55)
}

@Test func chatgptHandlesNullSecondary() throws {
    let json = """
    {"plan_type":"free","rate_limit":{"primary_window":{"used_percent":1,"limit_window_seconds":2592000,"reset_at":1793622392},"secondary_window":null}}
    """
    let u = try ChatGPTProvider.parse(Data(json.utf8))
    #expect(u.windows.map(\.label) == ["Monthly"])
}

@Test func copilotSkipsUnlimitedQuotas() throws {
    let json = """
    {"copilot_plan":"business","quota_reset_date":"2026-11-01","quota_snapshots":{
      "chat":{"unlimited":true,"percent_remaining":100},
      "premium_interactions":{"unlimited":false,"percent_remaining":73.0,"remaining":21928,"entitlement":30000}}}
    """
    let u = try CopilotProvider.parse(Data(json.utf8))
    #expect(u.plan == "Business")
    #expect(u.windows.count == 1)
    #expect(u.windows[0].label == "Premium requests")
    #expect(u.windows[0].usedPercent == 27)
    #expect(u.windows[0].detail == "8072 / 30000")
    #expect(u.windows[0].resetsAt != nil)
}

@Test func expectedPercentReflectsElapsedTime() {
    let now = Date()
    let w = UsageWindow(label: "Weekly", usedPercent: 10, resetsAt: now.addingTimeInterval(5 * 86400), duration: 7 * 86400)
    #expect(abs(w.expectedPercent(at: now)! - 200.0 / 7) < 0.001)
    #expect(UsageWindow(label: "x", usedPercent: 0, resetsAt: nil).expectedPercent(at: now) == nil)
    let past = UsageWindow(label: "x", usedPercent: 0, resetsAt: now.addingTimeInterval(-10), duration: 100)
    #expect(past.expectedPercent(at: now) == 100)
}

@Test func copilotWindowSpansPreviousMonth() throws {
    let json = """
    {"quota_reset_date":"2026-11-01","quota_snapshots":{"premium_interactions":{"unlimited":false,"percent_remaining":50}}}
    """
    let u = try CopilotProvider.parse(Data(json.utf8))
    #expect(u.windows[0].duration == TimeInterval(31 * 86400))
}

@Test func menuBarShowsSessionAndWeeklyWhenBothExist() {
    let both = ProviderUsage(plan: nil, windows: [
        UsageWindow(label: "Session (5h)", usedPercent: 80, resetsAt: nil, duration: 5 * 3600),
        UsageWindow(label: "Weekly", usedPercent: 30, resetsAt: nil, duration: 7 * 86400),
        UsageWindow(label: "Weekly Opus", usedPercent: 45, resetsAt: nil, duration: 7 * 86400),
        UsageWindow(label: "Extra usage", usedPercent: 99, resetsAt: nil),
    ])
    #expect(both.menuBarPercents == [80, 45])
    let monthly = ProviderUsage(plan: nil, windows: [
        UsageWindow(label: "Premium requests", usedPercent: 27, resetsAt: nil, duration: 31 * 86400),
    ])
    #expect(monthly.menuBarPercents == [27])
}

@Test func layoutReconcilesSavedPreferences() {
    let l = ProviderLayout(knownIDs: ["a", "b", "c"], savedOrder: ["c", "x", "a", "c"], hidden: ["a", "x"])
    #expect(l.order == ["c", "a", "b"])
    #expect(l.visible == ["c", "b"])
    let allHidden = ProviderLayout(knownIDs: ["a", "b"], hidden: ["a", "b"])
    #expect(allHidden.visible == ["a"])
}

@Test func layoutKeepsOneVisibleAndMoves() {
    var l = ProviderLayout(knownIDs: ["a", "b", "c"])
    l.setVisible("a", false)
    l.setVisible("b", false)
    #expect(!l.canToggle("c"))
    l.setVisible("c", false)
    #expect(l.visible == ["c"])
    l.setVisible("a", true)
    l.move("a", to: "c")
    #expect(l.order == ["b", "c", "a"])
    l.move("a", to: "b")
    #expect(l.order == ["a", "b", "c"])
}

@Test func usageRoundTripsThroughCodable() throws {
    let u = ProviderUsage(plan: "Pro", windows: [
        UsageWindow(label: "Weekly", usedPercent: 35, resetsAt: Date(timeIntervalSince1970: 1_800_000_000),
                    duration: 7 * 86400, detail: "x"),
    ])
    let decoded = try JSONDecoder().decode(ProviderUsage.self, from: JSONEncoder().encode(u))
    #expect(decoded == u)
    #expect(UsageError.rateLimited(retryAfter: 60).isRateLimited)
    #expect(UsageError.rateLimited(retryAfter: 60).retryAfter == 60)
    #expect(!UsageError.parse("x").isRateLimited)
}

@Test func retryAfterParsesSecondsAndHTTPDates() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(parseRetryAfter("2930", now: now) == 2930)
    #expect(parseRetryAfter(" 0 ", now: now) == 0)
    #expect(parseRetryAfter(nil, now: now) == nil)
    #expect(parseRetryAfter("soon", now: now) == nil)
    // 1_800_000_000 is Fri, 15 Jan 2027 08:00:00 GMT
    #expect(parseRetryAfter("Fri, 15 Jan 2027 08:10:00 GMT", now: now) == 600)
    #expect(parseRetryAfter("Fri, 15 Jan 2027 07:00:00 GMT", now: now) == 0)
}

@Test func cachedUsageRelevance() {
    let now = Date()
    let u = ProviderUsage(plan: nil, windows: [
        UsageWindow(label: "Session (5h)", usedPercent: 10, resetsAt: now.addingTimeInterval(3600), duration: 5 * 3600),
    ])
    #expect(u.isStillRelevant(fetchedAt: now.addingTimeInterval(-60), maxAge: 300, now: now))
    #expect(!u.isStillRelevant(fetchedAt: now.addingTimeInterval(-600), maxAge: 300, now: now))
    let reset = ProviderUsage(plan: nil, windows: [
        UsageWindow(label: "Session (5h)", usedPercent: 90, resetsAt: now.addingTimeInterval(-1), duration: 5 * 3600),
    ])
    #expect(!reset.isStillRelevant(fetchedAt: now.addingTimeInterval(-60), maxAge: 300, now: now))
}
