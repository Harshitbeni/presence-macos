import Foundation

@MainActor
@Observable
final class NowPlayingStore {
  var title: String = "—"
  var artist: String = "—"
  var artworkURL: String = ""
  var isPaused: Bool = false
  var onTrackChanged: ((String, String, String) -> Void)?

  nonisolated(unsafe) private var observer: NSObjectProtocol?

  init() {
    // Subscribe to Apple Music track-change notifications (no polling needed)
    observer = DistributedNotificationCenter.default().addObserver(
      forName: NSNotification.Name("com.apple.Music.playerInfo"),
      object: nil,
      queue: .main
    ) { [weak self] note in
      Task { @MainActor in self?.handleMusicNotification(note) }
    }

    // One-shot read for the case where music is already playing at launch
    if let current = MusicNowPlayingScript.currentPlaying() {
      title = current.title
      artist = current.artist
      Task {
        artworkURL = await Self.fetchArtworkURL(title: current.title, artist: current.artist)
      }
    }
  }

  deinit {
    if let observer {
      DistributedNotificationCenter.default().removeObserver(observer)
    }
  }

  private func handleMusicNotification(_ note: Notification) {
    let info = note.userInfo
    let state = info?["Player State"] as? String ?? ""
    let t: String
    let a: String
    if state == "Playing" {
      isPaused = false
      t = (info?["Name"] as? String) ?? "—"
      a = (info?["Artist"] as? String) ?? "—"
    } else if state == "Paused" {
      // Keep existing track info — just mark as paused
      isPaused = true
      return
    } else {
      // Stopped (Music app closed) — clear everything
      isPaused = false
      t = "—"
      a = "—"
    }
    guard t != title || a != artist else { return }
    title = t
    artist = a
    artworkURL = ""
    onTrackChanged?(t, a, "")
    // Fetch artwork async and broadcast again once we have the URL
    if t != "—" {
      Task {
        let url = await Self.fetchArtworkURL(title: t, artist: a)
        artworkURL = url
        onTrackChanged?(t, a, url)
      }
    }
  }

  private static func fetchArtworkURL(title: String, artist: String) async -> String {
    let term = "\(title) \(artist)"
    guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
          let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=1")
    else { return "" }
    guard let (data, _) = try? await URLSession.shared.data(from: url) else { return "" }
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let results = json["results"] as? [[String: Any]],
          let artwork = results.first?["artworkUrl100"] as? String
    else { return "" }
    return artwork.replacingOccurrences(of: "100x100bb", with: "300x300bb")
  }
}
