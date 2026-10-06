import Foundation
import Observation

/// Owns the clauth status feed.
///
/// Primary source is `~/.clauth/status.json`, which a running `clauth daemon`
/// rewrites every tick (≤1 s, atomic tmp + rename). The file is tiny, so we
/// simply re-read it on a short interval and compare bytes — the contract warns
/// that `(mtime, len)` can miss a real switch, a byte compare cannot.
///
/// When no daemon is publishing (stale `generated_at`), we fall back to
/// `clauth status --json`, which builds the same shape single-shot from the
/// on-disk caches (kept warm by an open clauth TUI, if any).
@MainActor
@Observable
final class FeedStore {
    enum DaemonHealth: Equatable {
        /// Feed rewritten within the last few seconds.
        case live
        /// Feed exists but has stopped advancing recently (daemon wedged/restarting).
        case stalling
        /// No daemon has published recently (or ever).
        case absent
    }

    enum Source: Equatable {
        case daemon
        case cli
        case staleFile
        case none
    }

    private(set) var feed: StatusFeed?
    private(set) var source: Source = .none
    private(set) var health: DaemonHealth = .absent
    private(set) var lastError: String?
    private(set) var clauthPath: String?
    private(set) var isStartingDaemon = false

    /// Called after every state change so the status item can re-render.
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private var fileFeed: StatusFeed?
    @ObservationIgnored private var cliFeed: StatusFeed?
    @ObservationIgnored private var cliFetchedAt: Date?
    @ObservationIgnored private var cliInFlight = false
    @ObservationIgnored private var lastFileData: Data?
    @ObservationIgnored private var timer: Timer?

    /// Respects `CLAUTH_HOME` if exported to GUI apps, else `~/.clauth`.
    let clauthHome: URL = {
        if let env = ProcessInfo.processInfo.environment["CLAUTH_HOME"], !env.isEmpty {
            return URL(fileURLWithPath: (env as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".clauth", isDirectory: true)
    }()

    var statusFileURL: URL { clauthHome.appendingPathComponent("status.json") }

    private let pollInterval: TimeInterval = 2
    /// Without a daemon, how often to rebuild the snapshot via the CLI.
    private let cliInterval: TimeInterval = 30
    /// The daemon publishes every ≤1 s; its watchdog aborts after 30 s without a tick.
    private let liveThreshold: TimeInterval = 10
    private let stallThreshold: TimeInterval = 45

    func start() {
        clauthPath = Self.locateClauth()
        poll()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Re-read the file now and force a CLI snapshot if no daemon is live.
    func refreshNow() {
        lastFileData = nil
        cliFetchedAt = nil
        if clauthPath == nil { clauthPath = Self.locateClauth() }
        poll()
    }

    private func poll() {
        readFile()
        updateHealth()
        if health != .live { fetchFromCLIIfDue() }
        recompute()
    }

    private func readFile() {
        guard let data = try? Data(contentsOf: statusFileURL) else {
            fileFeed = nil
            lastFileData = nil
            return
        }
        guard data != lastFileData else { return }
        lastFileData = data
        do {
            fileFeed = try StatusFeed.decode(data)
            lastError = nil
        } catch {
            // A torn read is impossible (atomic rename), so this is a real
            // shape problem; keep the last good feed and surface it.
            lastError = "status.json: \(error.localizedDescription)"
        }
    }

    private func updateHealth() {
        guard let stamp = fileFeed?.generatedAt else {
            health = .absent
            return
        }
        let age = Date().timeIntervalSince(stamp)
        if age < liveThreshold {
            health = .live
        } else if age < stallThreshold {
            health = .stalling
        } else {
            health = .absent
        }
    }

    private func recompute() {
        let newFeed: StatusFeed?
        let newSource: Source
        if health == .live, let fileFeed {
            newFeed = fileFeed
            newSource = .daemon
        } else if let cliFeed {
            newFeed = cliFeed
            newSource = .cli
        } else if let fileFeed {
            newFeed = fileFeed
            newSource = .staleFile
        } else {
            newFeed = nil
            newSource = .none
        }
        feed = newFeed
        source = newSource
        onChange?()
    }

    private func fetchFromCLIIfDue() {
        guard !cliInFlight, let path = clauthPath else { return }
        if let cliFetchedAt, Date().timeIntervalSince(cliFetchedAt) < cliInterval { return }
        cliInFlight = true
        Task {
            let result = await Self.run(path, ["status", "--json"])
            cliInFlight = false
            cliFetchedAt = Date()
            switch result {
            case .success(let data):
                do {
                    cliFeed = try StatusFeed.decode(data)
                    lastError = nil
                } catch {
                    lastError = "clauth status --json: \(error.localizedDescription)"
                }
            case .failure(let error):
                lastError = error.message
            }
            recompute()
        }
    }

    /// Spawn `clauth daemon` detached, the way the clauth TUI's `start daemon`
    /// does: from `~/.clauth`, stdout+stderr APPENDED to `daemon.log` (the
    /// daemon's in-place log trim requires an append-mode fd). A second daemon
    /// exits 0 on its own, so this is safe to click twice.
    func startDaemon() {
        guard let path = clauthPath, !isStartingDaemon else { return }
        isStartingDaemon = true
        onChange?()
        let home = clauthHome.path
        let script = #"cd "$1" && nohup "$2" daemon >> "$1/daemon.log" 2>&1 < /dev/null &"#
        Task {
            _ = await Self.run("/bin/sh", ["-c", script, "sh", home, path])
            try? await Task.sleep(for: .seconds(3))
            isStartingDaemon = false
            refreshNow()
        }
    }

    // MARK: - Process helpers

    struct RunError: Error {
        let message: String
    }

    nonisolated private static func run(_ executable: String, _ arguments: [String]) async -> Result<Data, RunError> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: .failure(RunError(message: error.localizedDescription)))
                    return
                }
                // Never let a wedged CLI pin this thread forever.
                DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
                    if process.isRunning { process.terminate() }
                }
                // Drain stderr concurrently so neither pipe can fill and block the child.
                nonisolated(unsafe) var err = Data()
                let errDone = DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    err = stderr.fileHandleForReading.readDataToEndOfFile()
                    errDone.signal()
                }
                let out = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                errDone.wait()

                if process.terminationStatus == 0 {
                    continuation.resume(returning: .success(out))
                } else {
                    let msg = String(data: err, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(returning: .failure(RunError(
                        message: msg.isEmpty ? "\(executable) exited \(process.terminationStatus)" : msg
                    )))
                }
            }
        }
    }

    /// GUI apps don't inherit the shell PATH, so probe the usual install
    /// locations. Override with `defaults write <bundle-id> clauthPath /path/to/clauth`.
    static func locateClauth() -> String? {
        let fm = FileManager.default
        if let custom = UserDefaults.standard.string(forKey: "clauthPath"),
           fm.isExecutableFile(atPath: (custom as NSString).expandingTildeInPath) {
            return (custom as NSString).expandingTildeInPath
        }
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/clauth",
            "\(home)/.cargo/bin/clauth",
            "/opt/homebrew/bin/clauth",
            "/usr/local/bin/clauth",
            "\(home)/bin/clauth",
        ]
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }
}
