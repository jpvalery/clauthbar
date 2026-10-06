import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = FeedStore()
    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusItemController(store: store)
        controller.install()
        self.controller = controller
        store.start()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu-bar only: no Dock icon even when launched as a bare executable.
app.setActivationPolicy(.accessory)
app.run()
