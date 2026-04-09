import AppKit

/// Reads the current track from Music.app when `MPNowPlayingInfoCenter` is empty (common for sandboxed helpers).
enum MusicNowPlayingScript {
  static func currentPlaying() -> (title: String, artist: String)? {
    let source = """
    tell application "Music"
      if not (running) then return ""
      if player state is not playing then return ""
      try
        set tn to name of current track as text
        set ta to artist of current track as text
        return tn & linefeed & ta
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

    let parts = combined.split(separator: "\n", omittingEmptySubsequences: false)
    let title = parts.first.map(String.init) ?? ""
    let artist = parts.count > 1 ? String(parts.dropFirst().joined(separator: "\n")) : ""
    let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let a = artist.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty && a.isEmpty { return nil }
    return (
      t.isEmpty ? "—" : t,
      a.isEmpty ? "—" : a
    )
  }
}
