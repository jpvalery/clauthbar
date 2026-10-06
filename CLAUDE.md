# ClauthBar agent notes

Read-only macOS menu bar display for clauth's status feed. SwiftPM only: no Xcode project, no xcodegen.

- **Build**: `swift build` to compile; `scripts/build-app.sh [--install|--zip]` to make the `.app`. The script generates `Info.plist`, so edit it there. It also builds `AppIcon.icns` from the repo-root `logo.png` via `scripts/make-icon.swift`; never commit a generated icon or the `.app`.
- **Data contract**: `~/.clauth/status.json` / `clauth status --json`, schema 2, documented at https://github.com/uwuclxdy/clauth/wiki/Daemon. Follow its evolution rule: ignore unknown fields, default absent ones, and refuse only on `schema > 2`. Window labels are opaque display strings; `5h` and `7d` are the only guaranteed ones.
- **Never** add switching, credential, or keychain code. ClauthBar is display-only by design.
- Swift 6 language mode, `@MainActor` UI/state. The status-item strip is rebuilt from a value snapshot (`StripSnapshot`) instead of observing state, because change delivery to SwiftUI hosted in an `NSStatusItem` button is unreliable.
