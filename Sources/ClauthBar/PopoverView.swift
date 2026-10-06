import ServiceManagement
import SwiftUI

private struct ListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Popover shown when clicking the status item: every profile clauth publishes,
/// with its usage windows, auth/fetch health, fallback position and the daemon state.
struct PopoverView: View {
    let store: FeedStore
    let onQuit: () -> Void

    @State private var listHeight: CGFloat = 200
    private let maxListHeight: CGFloat = 480

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 0) {
                header
                banners
                profileList(now: context.date)
                servicesLine
                Divider()
                footer
            }
            .frame(width: 340)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("clauth")
                .font(.system(size: 15, weight: .semibold))
            if let v = store.feed?.clauthVersion, !v.isEmpty {
                Text("v\(v)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            healthChip
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var healthChip: some View {
        let (text, color): (String, Color) = {
            switch store.health {
            case .live: return ("daemon live", .green)
            case .stalling: return ("daemon stalling", .orange)
            case .absent:
                switch store.source {
                case .cli: return ("no daemon · cached", .secondary)
                default: return ("no daemon", .secondary)
                }
            }
        }()
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .help(healthHelp)
    }

    private var healthHelp: String {
        switch store.source {
        case .daemon: return "Live feed from ~/.clauth/status.json"
        case .cli: return "No daemon publishing — snapshot from `clauth status --json` (refreshed every 30s). Usage only advances while a daemon or the clauth TUI is running."
        case .staleFile: return "No daemon publishing — showing the last status.json written."
        case .none: return "No clauth feed found."
        }
    }

    @ViewBuilder
    private var banners: some View {
        VStack(spacing: 6) {
            if let feed = store.feed, feed.schema > StatusFeed.supportedSchema {
                banner("clauth publishes schema \(feed.schema); ClauthBar understands \(StatusFeed.supportedSchema). Update ClauthBar.",
                       icon: "exclamationmark.triangle.fill", tint: .orange)
            }
            if let pending = store.feed?.pendingSwitch {
                banner("Switching to \(pending)…", icon: "arrow.triangle.2.circlepath", tint: .accentTick)
            }
            if store.feed == nil {
                if store.clauthPath == nil {
                    banner("clauth not found. Install it, or point ClauthBar at it:\ndefaults write \(Bundle.main.bundleIdentifier ?? "ClauthBar") clauthPath /path/to/clauth",
                           icon: "questionmark.circle", tint: .secondary)
                } else {
                    banner("No status feed yet at \(store.statusFileURL.path).", icon: "hourglass", tint: .secondary)
                }
            }
            if let err = store.lastError {
                banner(err, icon: "xmark.octagon", tint: .red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, store.feed?.pendingSwitch != nil || store.lastError != nil || store.feed == nil ? 8 : 0)
    }

    private func banner(_ text: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text)
                .font(.system(size: 11))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.12)))
    }

    // MARK: Profiles

    private var orderedProfiles: [StatusFeed.Profile] {
        guard let feed = store.feed, let profiles = feed.profiles else { return [] }
        // Active Claude Code profile first, then the published order (codex trails).
        let active = profiles.filter { !$0.isCodex && $0.name == feed.activeProfile }
        return active + profiles.filter { $0.isCodex || $0.name != feed.activeProfile }
    }

    @ViewBuilder
    private func profileList(now: Date) -> some View {
        let profiles = orderedProfiles
        if !profiles.isEmpty {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(profiles) { profile in
                        ProfileCard(
                            profile: profile,
                            isActive: isActive(profile),
                            dimmed: store.source == .staleFile,
                            now: now
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ListHeightKey.self, value: geo.size.height)
                    }
                )
            }
            .scrollIndicators(listHeight > maxListHeight ? .automatic : .never)
            .frame(height: min(listHeight, maxListHeight))
            .onPreferenceChange(ListHeightKey.self) { h in
                if h > 0 { listHeight = h }
            }
        }
    }

    private func isActive(_ profile: StatusFeed.Profile) -> Bool {
        guard let feed = store.feed else { return false }
        return profile.isCodex ? profile.name == feed.activeCodexProfile : profile.name == feed.activeProfile
    }

    // MARK: Gateway / proxies

    @ViewBuilder
    private var servicesLine: some View {
        let items = serviceItems
        if !items.isEmpty {
            HStack(spacing: 10) {
                ForEach(items, id: \.0) { name, state in
                    HStack(spacing: 4) {
                        Circle().fill(serviceColor(state)).frame(width: 6, height: 6)
                        Text("\(name) \(state)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    private var serviceItems: [(String, String)] {
        var items: [(String, String)] = []
        if let g = store.feed?.gateway, let state = g.state, state != "absent" {
            items.append(("shunt" + (g.port.map { " :\($0)" } ?? ""), state))
        }
        for p in store.feed?.proxies ?? [] {
            if let service = p.service, let state = p.state, state != "absent" {
                items.append((service, state))
            }
        }
        return items
    }

    private func serviceColor(_ state: String) -> Color {
        switch state {
        case "healthy": return .green
        case "starting", "restarting", "stopping", "unhealthy": return .orange
        case "disabled", "held", "unobserved": return .secondary
        default: return .red
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if store.health != .live, store.clauthPath != nil {
                Button {
                    store.startDaemon()
                } label: {
                    Label(store.isStartingDaemon ? "Starting…" : "Start daemon", systemImage: "play.fill")
                }
                .disabled(store.isStartingDaemon)
                .help("Runs `clauth daemon` in the background (log: ~/.clauth/daemon.log)")
            }

            Button {
                store.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload now")

            Spacer()

            OptionsMenu(store: store)

            Button(action: onQuit) {
                Image(systemName: "power")
            }
            .help("Quit ClauthBar")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - Profile card

private struct ProfileCard: View {
    let profile: StatusFeed.Profile
    let isActive: Bool
    let dimmed: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            titleRow
            issues
            if let windows = profile.windows, !windows.isEmpty {
                VStack(spacing: 4) {
                    ForEach(windows) { WindowRow(window: $0, now: now) }
                }
                .opacity(profile.isStale || dimmed ? 0.5 : 1)
            } else {
                Text(profile.thirdParty != nil ? "No usage windows published for this provider" : "No usage reading yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            footnote
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? Color.accentTick.opacity(0.10) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isActive ? Color.accentTick.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            if profile.hasLiveSession == true {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .help("Live Claude Code session on this account")
            }
            Text(profile.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            if let tier = profile.tier {
                Tag(text: tier, tint: .secondary)
            }
            if profile.isCodex {
                Tag(text: "codex", tint: .blue)
            } else if let provider = profile.provider, provider != "anthropic" {
                Tag(text: provider, tint: .purple)
            }
            Spacer(minLength: 4)
            if let fb = profile.fallback, let pos = fb.position {
                Text("#\(pos)" + (fb.threshold.map { " @\(Int($0))%" } ?? ""))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(fb.armed == true ? Color.accentTick : .secondary)
                    .help(fb.armed == true ? "Fallback chain: armed (auto-switch watching this one)" : "Fallback chain position")
            }
            if isActive {
                Tag(text: "ACTIVE", tint: .accentTick, filled: true)
            }
        }
    }

    @ViewBuilder
    private var issues: some View {
        let list = issueList
        if !list.isEmpty {
            HStack(spacing: 4) {
                ForEach(list, id: \.0) { text, tint in
                    Tag(text: text, tint: tint)
                }
            }
        }
    }

    private var issueList: [(String, Color)] {
        var out: [(String, Color)] = []
        switch profile.auth {
        case "broken": out.append(("auth broken", .red))
        case "expired": out.append(("token expired", .orange))
        default: break
        }
        switch profile.fetchStatus {
        case "AuthExpired": out.append(("credential dead", .red))
        case "Failed": out.append(("fetch failed", .orange))
        case "RateLimited": out.append(("rate limited", .orange))
        default: break
        }
        if profile.isStale { out.append(("stale", .orange)) }
        if profile.thirdParty?.available == false { out.append(("unreachable", .red)) }
        return out
    }

    private var footnote: some View {
        HStack(spacing: 4) {
            if let age = Fmt.age(of: profile.fetchedAt, now: now) {
                Text("read \(age)")
            } else {
                Text("undated reading")
            }
            if let status = profile.fetchStatus {
                Text("·")
                Text(status)
            }
            Spacer()
            if profile.fetchStatus != "AuthExpired",
               let next = profile.nextRefreshAt, next > now,
               let s = Fmt.countdown(to: next, now: now) {
                Text("next in \(s)")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
    }
}

private struct WindowRow: View {
    let window: StatusFeed.Window
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Text(window.label)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 58, alignment: .leading)
                .lineLimit(1)
            UsageMeter(
                percent: window.utilizationPct,
                pace: window.elapsedPercent(now: now),
                tint: utilizationColor(window.utilizationPct, monochrome: false),
                width: 140,
                height: 9
            )
            Text(Fmt.percent(window.utilizationPct))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .frame(width: 36, alignment: .trailing)
            Text(Fmt.countdown(to: window.resetsAt, now: now).map { "↻ \($0)" } ?? "")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
                .help(window.resetsAt.map { "Resets \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "No reset time published")
        }
    }
}

private struct Tag: View {
    let text: String
    let tint: Color
    var filled = false

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .foregroundStyle(filled ? Color.white : tint)
            .background(Capsule().fill(filled ? tint : tint.opacity(0.15)))
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - Options

private struct OptionsMenu: View {
    let store: FeedStore

    @AppStorage(PrefKey.showName) private var showName = true
    @AppStorage(PrefKey.showSession) private var showSession = true
    @AppStorage(PrefKey.showWeekly) private var showWeekly = true
    @AppStorage(PrefKey.showPercentText) private var showPercentText = false
    @AppStorage(PrefKey.showPace) private var showPace = true
    @AppStorage(PrefKey.showSessionReset) private var showSessionReset = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Menu {
            Section("Menu bar") {
                Toggle("Profile name", isOn: $showName)
                Toggle("5h session", isOn: $showSession)
                Toggle("5h reset countdown", isOn: $showSessionReset)
                Toggle("7d weekly", isOn: $showWeekly)
                Toggle("Percentages instead of bars", isOn: $showPercentText)
                Toggle("Pace tick on bars", isOn: $showPace)
                    .disabled(showPercentText)
            }
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            NSLog("ClauthBar: launch-at-login change failed: \(error)")
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                ))
                Button("Reveal status.json in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.statusFileURL])
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Display options")
    }
}
