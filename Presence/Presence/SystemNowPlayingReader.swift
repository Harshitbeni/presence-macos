import Foundation
import MediaPlayer

/// Reads system-wide now-playing metadata (Music, Spotify, etc.) from `MPNowPlayingInfoCenter`.
enum SystemNowPlayingReader {
  static func read() -> (title: String, artist: String, isPaused: Bool, trackID: String)? {
    guard let info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return nil }

    var rawTitle = (info[MPMediaItemPropertyTitle] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if rawTitle.isEmpty {
      rawTitle = (info[MPMediaItemPropertyAlbumTitle] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    let rawArtist = (info[MPMediaItemPropertyArtist] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if rawTitle.isEmpty && rawArtist.isEmpty { return nil }

    // If Music omits playback rate, don't treat as paused (rate defaults to 0 below).
    let isPaused: Bool
    if info[MPNowPlayingInfoPropertyPlaybackRate] != nil {
      isPaused = playbackRate(from: info) <= 0.001
    } else {
      isPaused = false
    }

    return (
      rawTitle.isEmpty ? "—" : rawTitle,
      rawArtist.isEmpty ? "—" : rawArtist,
      isPaused,
      trackID(from: info)
    )
  }

  private static func playbackRate(from info: [String: Any]) -> Double {
    if let d = info[MPNowPlayingInfoPropertyPlaybackRate] as? Double { return d }
    if let n = info[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber { return n.doubleValue }
    return 0
  }

  private static func trackID(from info: [String: Any]) -> String {
    if let storeID = info[MPMediaItemPropertyPlaybackStoreID] as? String {
      return storeID.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let persistent = info[MPMediaItemPropertyPersistentID] as? NSNumber {
      return persistent.stringValue
    }
    if let persistentUInt64 = info[MPMediaItemPropertyPersistentID] as? UInt64 {
      return String(persistentUInt64)
    }
    return ""
  }
}
