import Foundation

/// Read model for clauth's `~/.clauth/status.json` (schema 2), also printed by
/// `clauth status --json`. Contract: https://github.com/uwuclxdy/clauth/wiki/Daemon
///
/// Per the contract's evolution rule, readers ignore unknown fields and default
/// absent optional ones, so everything except `schema` is optional here.
struct StatusFeed: Decodable, Equatable {
    /// Highest schema this reader understands. A newer feed is refused with a
    /// "daemon newer than me" cue rather than rendered as garbage.
    static let supportedSchema = 2

    var schema: Int
    var generatedAt: Date?
    var activeProfile: String?
    var pendingSwitch: String?
    var wrapOff: Bool?
    var activeCodexProfile: String?
    var codexFallbackChain: [String]?
    var refreshIntervalMs: Int?
    var clauthVersion: String?
    var gateway: Gateway?
    var proxies: [Proxy]?
    var profiles: [Profile]?

    struct Gateway: Decodable, Equatable {
        var state: String?
        var port: Int?
        var version: String?
        var reason: String?
    }

    struct Proxy: Decodable, Equatable {
        var service: String?
        var state: String?
        var port: Int?
        var reason: String?
    }

    struct Profile: Decodable, Equatable, Identifiable {
        var name: String
        var active: Bool?
        var rollingToken: Bool?
        var provider: String?
        var tier: String?
        var harness: String?
        var hasLiveSession: Bool?
        var authStatus: String?
        var fetchStatus: String?
        var stale: Bool?
        var fetchedAt: Date?
        var nextRefreshAt: Date?
        var fallback: Fallback?
        var windows: [Window]?
        var thirdParty: ThirdParty?

        var id: String { name }
        var isCodex: Bool { (harness ?? "claude") == "codex" }
        var auth: String { authStatus ?? "ok" }
        var isStale: Bool { stale ?? false }

        /// The 5-hour session window, if it is currently listed.
        var sessionWindow: Window? { windows?.first { $0.label == "5h" } }

        /// The weekly window. Labels are opaque per the contract, but `"7d"`
        /// is always the plain weekly one; some plans (e.g. Team) only publish
        /// a tier-labelled weekly window such as `"7d fable"`, so fall back to
        /// the first `7d*` label.
        var weeklyWindow: Window? {
            windows?.first { $0.label == "7d" }
                ?? windows?.first { $0.label.lowercased().hasPrefix("7d") }
        }
    }

    struct Fallback: Decodable, Equatable {
        var position: Int?
        var threshold: Double?
        var armed: Bool?
    }

    struct Window: Decodable, Equatable, Identifiable {
        var label: String
        var utilizationPct: Double?
        var resetsAt: Date?

        var id: String { label }

        /// Nominal window length used for the "time elapsed" pace tick.
        var nominalSeconds: TimeInterval? {
            let l = label.lowercased()
            if l.hasPrefix("5h") { return 5 * 3600 }
            if l.hasPrefix("7d") { return 7 * 86400 }
            return nil
        }

        /// Percentage (0–100) of the window already elapsed, or nil when the
        /// reset instant or the window length is unknown.
        func elapsedPercent(now: Date = Date()) -> Double? {
            guard let resetsAt, let length = nominalSeconds else { return nil }
            let remaining = resetsAt.timeIntervalSince(now)
            guard remaining >= 0 else { return nil }
            return min(max((length - remaining) / length * 100, 0), 100)
        }
    }

    struct ThirdParty: Decodable, Equatable {
        var available: Bool?
    }

    var activeClaudeProfile: Profile? {
        guard let activeProfile else { return nil }
        return profiles?.first { $0.name == activeProfile }
    }

    static func decode(_ data: Data) throws -> StatusFeed {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = parseTimestamp(raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unparseable timestamp: \(raw)"
            )
        }
        return try decoder.decode(StatusFeed.self, from: data)
    }

    /// clauth writes ISO-8601 with an explicit `+00:00` offset, sometimes with
    /// microsecond fractions (`…59.815736+00:00`).
    static func parseTimestamp(_ raw: String) -> Date? {
        if let d = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(raw) { return d }
        return try? Date.ISO8601FormatStyle().parse(raw)
    }
}
