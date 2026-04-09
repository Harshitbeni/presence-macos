import AppKit

/// Fallback when `MPNowPlayingInfoCenter` has no metadata (Automation + Music.app).
enum MusicNowPlayingScript {
  private static let fieldSep = "\u{001F}"

  /// Runs a trivial script so Hardened Runtime + TCC can show the Automation prompt and list Presence under Privacy.
  /// Requires `com.apple.security.automation.apple-events` in entitlements alongside the sandbox Music exception.
  static func primeAutomationAccess() {
    let source = """
    tell application "Music" to get version
    """
    var error: NSDictionary?
    guard let script = NSAppleScript(source: source) else { return }
    _ = script.executeAndReturnError(&error)
  }

  /// Reads the current track whenever Music is not stopped (playing, paused, scrubbing, etc.).
  /// Avoids `player state is not playing` — streaming often reports odd states while audio is active.
  static func currentPlaying() -> (title: String, artist: String, isPaused: Bool)? {
    let source = """
    set sep to ASCII character 31
    tell application "Music"
      if not (running) then return ""
      if player state is stopped then return ""
      try
        set tn to name of current track as text
        set ta to artist of current track as text
        set pausedBit to "0"
        if player state is paused then set pausedBit to "1"
        return tn & sep & ta & sep & pausedBit
      on error
        return ""
      end try
    end tell
    return ""
    """
    var error: NSDictionary?
    guard let script = NSAppleScript(source: source) else { return nil }
    let result = script.executeAndReturnError(&error)
    if error != nil { return nil }
    guard let combined = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
          !combined.isEmpty
    else { return nil }

    let parts = combined.components(separatedBy: fieldSep)
    guard parts.count >= 2 else { return nil }
    let title = String(parts[0])
    let artist = String(parts[1])
    let pausedBit = parts.count > 2 ? String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines) : "0"
    let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let a = artist.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty && a.isEmpty { return nil }
    return (
      t.isEmpty ? "—" : t,
      a.isEmpty ? "—" : a,
      pausedBit == "1"
    )
  }
}
