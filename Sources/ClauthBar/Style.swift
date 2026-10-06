import SwiftUI

extension Color {
    /// App accent (#E86D45): active profile, pace tick, armed fallback.
    static let accentTick = Color(red: 0xE8 / 255.0, green: 0x6D / 255.0, blue: 0x45 / 255.0)
}

enum Fmt {
    /// Compact countdown: `45m`, `2h13m`, `3d4h`.
    static func countdown(to date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let secs = Int(date.timeIntervalSince(now))
        guard secs > 0 else { return "now" }
        let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
        if d > 0 { return h > 0 ? "\(d)d\(h)h" : "\(d)d" }
        if h > 0 { return m > 0 ? "\(h)h\(m)m" : "\(h)h" }
        return "\(max(m, 1))m"
    }

    /// Relative age: `just now`, `3m ago`, `2h ago`.
    static func age(of date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let secs = Int(now.timeIntervalSince(date))
        if secs < 45 { return "just now" }
        if secs < 3600 { return "\(max(secs / 60, 1))m ago" }
        if secs < 86400 { return "\(secs / 3600)h ago" }
        return "\(secs / 86400)d ago"
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))%"
    }
}

/// Fill color for a utilization meter. In the menu bar it stays monochrome so it
/// follows the light/dark bar, turning orange/red only near the limit.
func utilizationColor(_ pct: Double?, monochrome: Bool) -> Color {
    guard let pct else { return .secondary }
    if pct >= 90 { return .red }
    if pct >= 75 { return .orange }
    return monochrome ? .primary : .accentTick
}

/// User display preferences for the menu bar strip (stored in UserDefaults).
enum PrefKey {
    static let showName = "showName"
    static let showSession = "showSession"
    static let showWeekly = "showWeekly"
    static let showPercentText = "showPercentText"
    static let showPace = "showPace"
    static let showSessionReset = "showSessionReset"
}

struct DisplayPrefs: Equatable {
    var showName = true
    var showSession = true
    var showWeekly = true
    var showPercentText = false
    var showPace = true
    var showSessionReset = false

    static func load() -> DisplayPrefs {
        let d = UserDefaults.standard
        func b(_ key: String, _ fallback: Bool) -> Bool {
            d.object(forKey: key) == nil ? fallback : d.bool(forKey: key)
        }
        let def = DisplayPrefs()
        return DisplayPrefs(
            showName: b(PrefKey.showName, def.showName),
            showSession: b(PrefKey.showSession, def.showSession),
            showWeekly: b(PrefKey.showWeekly, def.showWeekly),
            showPercentText: b(PrefKey.showPercentText, def.showPercentText),
            showPace: b(PrefKey.showPace, def.showPace),
            showSessionReset: b(PrefKey.showSessionReset, def.showSessionReset)
        )
    }
}
