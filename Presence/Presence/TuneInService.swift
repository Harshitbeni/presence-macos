import AppKit
import Foundation

@MainActor
enum TuneInService {
  static func tuneIn(peerTitle: String, peerArtist: String, peerTrackID: String) async -> String? {
    let term = "\(peerTitle) \(peerArtist)".trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedTrackID = peerTrackID.trimmingCharacters(in: .whitespacesAndNewlines)

    if !normalizedTrackID.isEmpty {
      if let musicURL = await lookupTrackURL(trackID: normalizedTrackID) {
        openMusicURLInBackground(musicURL)
        return nil
      }
    }

    guard !term.isEmpty, term != "——" else { return "No remote track" }

    guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
          let searchURL = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=1")
    else { return "Search failed" }

    guard let (data, _) = try? await URLSession.shared.data(from: searchURL) else {
      return "Network error"
    }
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let results = json["results"] as? [[String: Any]],
          let first = results.first,
          let trackViewUrl = first["trackViewUrl"] as? String,
          let musicURL = URL(string: trackViewUrl)
    else { return "No catalog match" }

    openMusicURLInBackground(musicURL)
    return nil
  }

  private static func lookupTrackURL(trackID: String) async -> URL? {
    guard let encoded = trackID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
          let lookupURL = URL(string: "https://itunes.apple.com/lookup?id=\(encoded)")
    else { return nil }

    guard let (data, _) = try? await URLSession.shared.data(from: lookupURL) else {
      return nil
    }
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let results = json["results"] as? [[String: Any]],
          let first = results.first,
          let trackViewUrl = first["trackViewUrl"] as? String,
          let musicURL = URL(string: trackViewUrl)
    else { return nil }
    return musicURL
  }

  private static func openMusicURLInBackground(_ musicURL: URL) {
    // Open without activating Music.app so it stays in the background
    let config = NSWorkspace.OpenConfiguration()
    config.activates = false
    NSWorkspace.shared.open(musicURL, configuration: config) { _, _ in }
  }
}

// ARCHIVE — original implementation (opened Music in foreground)
//
// if NSWorkspace.shared.open(musicURL) { return nil }
// return "Could not open Music"
