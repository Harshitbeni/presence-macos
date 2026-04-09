import AppKit

/// Holds a strong reference because `NSApplication.delegate` is weak.
private let presenceAppDelegate = AppDelegate()

@main
enum PresenceEntry {
  static func main() {
    let app = NSApplication.shared
    app.delegate = presenceAppDelegate
    app.setActivationPolicy(.regular)
    app.run()
  }
}
