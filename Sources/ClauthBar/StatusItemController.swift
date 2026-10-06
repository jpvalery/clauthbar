import AppKit
import SwiftUI

/// Owns the menu-bar `NSStatusItem` and its click-through `NSPopover`.
///
/// Uses `NSStatusItem` directly (not `MenuBarExtra`) so the label can host a
/// multi-element, two-line SwiftUI strip.
@MainActor
final class StatusItemController: NSObject {
    private let store: FeedStore
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var stripController: NSHostingController<MenuBarStripView>?
    private var tickTimer: Timer?
    private var lastRendered: RenderKey?

    private struct RenderKey: Equatable {
        var feed: StatusFeed?
        var source: FeedStore.Source
        var health: FeedStore.DaemonHealth
        var prefs: DisplayPrefs
    }

    init(store: FeedStore) {
        self.store = store
        super.init()
    }

    func install() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        let strip = NSHostingController(rootView: makeStrip())
        strip.sizingOptions = [.intrinsicContentSize]
        stripController = strip

        let stripView = strip.view
        stripView.translatesAutoresizingMaskIntoConstraints = false
        if let button = statusItem.button {
            button.addSubview(stripView)
            // Center only, and drive the status item length from the strip's
            // reported width: pinning the strip to the button's edges lets the
            // initially-narrow button truncate the strip, which then sticks.
            NSLayoutConstraint.activate([
                stripView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                stripView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.setAccessibilityLabel("clauth usage")
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        let content = NSHostingController(rootView: PopoverView(store: store, onQuit: { NSApp.terminate(nil) }))
        content.sizingOptions = [.preferredContentSize]
        popover.contentViewController = content
        self.popover = popover

        store.onChange = { [weak self] in self?.refreshStrip() }
        NotificationCenter.default.addObserver(
            self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil
        )
        // Keeps countdowns and pace ticks moving between feed changes.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStrip(force: true) }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    @objc private func defaultsChanged() {
        refreshStrip()
    }

    private func makeStrip() -> MenuBarStripView {
        let statusItem = self.statusItem
        return MenuBarStripView(
            snapshot: StripSnapshot(
                feed: store.feed,
                source: store.source,
                health: store.health,
                prefs: DisplayPrefs.load(),
                now: Date()
            ),
            onWidth: { [weak statusItem] width in
                statusItem?.length = max(width, 1)
            }
        )
    }

    /// Rebuild the strip only when something it renders changed: the store
    /// polls every 2 s and the daemon rewrites `generated_at` every tick.
    private func refreshStrip(force: Bool = false) {
        let strip = makeStrip()
        var feed = strip.snapshot.feed
        feed?.generatedAt = nil
        let key = RenderKey(feed: feed, source: store.source, health: store.health, prefs: strip.snapshot.prefs)
        guard force || key != lastRendered else { return }
        lastRendered = key
        stripController?.rootView = strip
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            store.refreshNow()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
