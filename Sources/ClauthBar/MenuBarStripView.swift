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
            Label("clauth newer than ClauthBar", systemImage: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .medium))
        } else if snapshot.feed == nil {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 13))
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
