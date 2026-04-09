import AppKit
import Foundation

@MainActor
enum TuneInService {
  static func tuneIn(peerTitle: String, peerArtist: String) async -> String? {
    let term = "\(peerTitle) \(peerArtist)".trimmingCharacters(in: .whitespacesAndNewlines)
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

    if NSWorkspace.shared.open(musicURL) { return nil }
    return "Could not open Music"
  }
}
