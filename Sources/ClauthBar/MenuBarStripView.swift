import SwiftUI

private struct StripWidthKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Plain value snapshot rendered inside the NSStatusItem button.
///
/// Deliberately a value type rebuilt by the controller rather than an observing
/// view: change delivery to SwiftUI hosted inside a status item button is
/// unreliable, so the controller pushes a fresh snapshot instead.
struct StripSnapshot {
    var feed: StatusFeed?
    var source: FeedStore.Source
    var health: FeedStore.DaemonHealth
    var prefs: DisplayPrefs
    var now: Date
}

/// iStats-style menu bar content: active profile name followed by two-line
/// `5H` / `7D` modules (label on top, meter or value below).
struct MenuBarStripView: View {
    let snapshot: StripSnapshot
    let onWidth: (CGFloat) -> Void

    private var profile: StatusFeed.Profile? { snapshot.feed?.activeClaudeProfile }

    /// Dim the readings when nobody is maintaining them.
    private var isDimmed: Bool {
        if profile?.isStale == true { return true }
        switch snapshot.source {
        case .daemon, .cli: return false
        case .staleFile, .none: return true
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            content
        }
        .padding(.horizontal, 5)
        .frame(height: 22)
        .fixedSize()
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: StripWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(StripWidthKey.self) { width in
            if width > 0 { onWidth(width) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let feed = snapshot.feed, feed.schema > StatusFeed.supportedSchema {
            if snapshot.prefs.compact {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13))
            } else {
                Label("clauth newer than ClauthBar", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .medium))
            }
        } else if snapshot.feed == nil {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 13))
        } else if snapshot.prefs.compact {
            ProfileLinesGlyph(
                profiles: snapshot.feed?.profiles ?? [],
                activeProfile: snapshot.feed?.activeProfile,
                dimAll: snapshot.source == .staleFile || snapshot.source == .none
            )
        } else {
            let prefs = snapshot.prefs
            if prefs.showName || profile == nil {
                nameView
            }
            if let profile {
                Group {
                    if prefs.showSession {
                        module(label: "5H", window: profile.sessionWindow)
                    }
                    if prefs.showSessionReset {
                        valueModule(label: "5H↻", value: Fmt.countdown(to: profile.sessionWindow?.resetsAt, now: snapshot.now) ?? "—")
                    }
                    if prefs.showWeekly {
                        module(label: "7D", window: profile.weeklyWindow)
                    }
                }
                .opacity(isDimmed ? 0.45 : 1)
            }
        }
    }

    private var nameView: some View {
        HStack(spacing: 3) {
            if let profile, profile.auth != "ok" {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }
            Text(nameText)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .fixedSize()
        }
        .opacity(snapshot.health == .live ? 1 : 0.7)
    }

    private var nameText: String {
        guard let feed = snapshot.feed else { return "clauth" }
        let active = feed.activeProfile ?? "—"
        if let pending = feed.pendingSwitch, pending != active {
            return "\(active) → \(pending)"
        }
        return active
    }

    private func module(label: String, window: StatusFeed.Window?) -> some View {
        twoLine(label: label) {
            if snapshot.prefs.showPercentText {
                Text(Fmt.percent(window?.utilizationPct))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(utilizationColor(window?.utilizationPct, monochrome: true))
                    .fixedSize()
            } else {
                UsageMeter(
                    percent: window?.utilizationPct,
                    pace: snapshot.prefs.showPace ? window?.elapsedPercent(now: snapshot.now) : nil,
                    tint: utilizationColor(window?.utilizationPct, monochrome: true)
                )
            }
        }
    }

    private func valueModule(label: String, value: String) -> some View {
        twoLine(label: label) {
            Text(value)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .fixedSize()
        }
    }

    private func twoLine<V: View>(label: String, @ViewBuilder value: () -> V) -> some View {
        VStack(alignment: .center, spacing: 0) {
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .kerning(0.2)
                .fixedSize()
                .frame(height: 9)
            value()
                .frame(height: 13)
        }
        .fixedSize()
    }
}

/// Compact menu bar mode: one horizontal line per profile, in published order,
/// stacked inside a single square and colored by 5h utilization (green, then
/// orange at 75%, red at 90%). A profile with no 5h reading draws faint gray.
/// The active Claude Code profile's line starts further left than the rest so
/// it can be picked out without a label. Order stays stable across switches so
/// each line keeps meaning the same account.
struct ProfileLinesGlyph: View {
    let profiles: [StatusFeed.Profile]
    let activeProfile: String?
    let dimAll: Bool

    static let side: CGFloat = 16
    /// Beyond this the lines get thinner than a pixel on non-Retina displays.
    static let maxLines = 8

    private var shown: ArraySlice<StatusFeed.Profile> { profiles.prefix(Self.maxLines) }
    private var gap: CGFloat { shown.count <= 5 ? 2 : 1 }
    private var thickness: CGFloat {
        let n = CGFloat(max(shown.count, 1))
        return min(3, (Self.side - gap * (n - 1)) / n)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            ForEach(shown) { profile in
                line(for: profile)
            }
        }
        .frame(width: Self.side, height: Self.side)
    }

    private func line(for profile: StatusFeed.Profile) -> some View {
        let isActive = !profile.isCodex && profile.name == activeProfile
        let leading: CGFloat = isActive ? 0 : 3
        return Capsule()
            .fill(Self.color(for: profile))
            .frame(width: Self.side - leading, height: thickness)
            .padding(.leading, leading)
            .opacity(dimAll || profile.isStale ? 0.45 : 1)
    }

    static func color(for profile: StatusFeed.Profile) -> Color {
        guard let pct = profile.sessionWindow?.utilizationPct else {
            return Color.primary.opacity(0.3)
        }
        if pct >= 90 { return .red }
        if pct >= 75 { return .orange }
        return .green
    }
}

/// Outlined pill meter for a 0–100 utilization. Missing data draws a dashed,
/// empty outline so "unknown" never reads as 0%. `pace` (0–100) adds a thin
/// accent tick at the share of the window already elapsed: a fill past the
/// tick means usage is outrunning the clock.
struct UsageMeter: View {
    let percent: Double?
    var pace: Double? = nil
    let tint: Color
    var width: CGFloat = 26
    var height: CGFloat = 8

    private let inset: CGFloat = 1.5
    private var innerWidth: CGFloat { width - inset * 2 }
    private var innerHeight: CGFloat { height - inset * 2 }

    private func fraction(_ value: Double) -> CGFloat {
        CGFloat(min(max(value / 100, 0), 1))
    }

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2)
            .strokeBorder(
                Color.primary.opacity(percent == nil ? 0.25 : 0.55),
                style: StrokeStyle(lineWidth: 1, dash: percent == nil ? [2, 2] : [])
            )
            .frame(width: width, height: height)
            .overlay(alignment: .leading) {
                if let percent {
                    RoundedRectangle(cornerRadius: innerHeight / 2)
                        .fill(tint)
                        .frame(width: innerWidth * fraction(percent), height: innerHeight)
                        .offset(x: inset)
                }
            }
            .overlay(alignment: .leading) {
                if percent != nil, let pace {
                    Rectangle()
                        .fill(Color.accentTick)
                        .frame(width: 1.5, height: height - 1)
                        .offset(x: inset + innerWidth * fraction(pace) - 0.75)
                }
            }
    }
}
