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
  /// Only touched from the main queue; `nonisolated(unsafe)` so `deinit` can cancel pending work.
  nonisolated(unsafe) private var catchUpWorkItems: [DispatchWorkItem] = []

  init() {
    // Subscribe to Apple Music track-change notifications (no polling needed)
    observer = DistributedNotificationCenter.default().addObserver(
      forName: NSNotification.Name("com.apple.Music.playerInfo"),
      object: nil,
      queue: .main
    ) { [weak self] note in
      Task { @MainActor in self?.handleMusicNotification(note) }
    }
  }

  /// Syncs from `MPNowPlayingInfoCenter`, then AppleScript if needed. Call after launch and when opening the panel.
  func refreshFromSystem() {
    let newTitle: String
    let newArtist: String
    let newPaused: Bool
    if let system = SystemNowPlayingReader.read() {
      newTitle = system.title
      newArtist = system.artist
      newPaused = system.isPaused
    } else if let script = MusicNowPlayingScript.currentPlaying() {
      newTitle = script.title
      newArtist = script.artist
      newPaused = script.isPaused
    } else {
      return
    }

    let trackChanged = newTitle != title || newArtist != artist
    let pauseChanged = newPaused != isPaused

    if trackChanged {
      title = newTitle
      artist = newArtist
      isPaused = newPaused
      artworkURL = ""
      onTrackChanged?(newTitle, newArtist, "")
      if newTitle != "—" {
        Task {
          let url = await Self.fetchArtworkURL(title: newTitle, artist: newArtist)
          artworkURL = url
          onTrackChanged?(newTitle, newArtist, url)
        }
      }
    } else if pauseChanged {
      isPaused = newPaused
    }
  }

  /// Several delayed refreshes — `MPNowPlayingInfoCenter` and Music scripting often lag right after launch.
  func scheduleCatchUpRefreshAttempts() {
    catchUpWorkItems.forEach { $0.cancel() }
    catchUpWorkItems.removeAll()
    let delays: [TimeInterval] = [0.25, 0.75, 1.5, 3, 6, 10]
    for delay in delays {
      let work = DispatchWorkItem { [weak self] in
        self?.refreshFromSystem()
      }
      catchUpWorkItems.append(work)
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
  }

  deinit {
    catchUpWorkItems.forEach { $0.cancel() }
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
