import Foundation

@MainActor
@Observable
final class NowPlayingStore {
  var title: String = "—"
  var artist: String = "—"
  var artworkURL: String = ""
  var trackID: String = ""
  var isPaused: Bool = false
  var onTrackChanged: ((String, String, String, String) -> Void)?

  nonisolated(unsafe) private var observer: NSObjectProtocol?
  nonisolated(unsafe) private var catchUpWorkItems: [DispatchWorkItem] = []
  nonisolated(unsafe) private var periodicRefreshTask: Task<Void, Never>?

  init() {
    observer = DistributedNotificationCenter.default().addObserver(
      forName: NSNotification.Name("com.apple.Music.playerInfo"),
      object: nil,
      queue: .main
    ) { [weak self] note in
      Task { @MainActor in self?.handleMusicNotification(note) }
    }
    startPeriodicRefresh()
  }

  func refreshFromSystem() {
    guard let system = SystemNowPlayingReader.read() else { return }
    let scripted = MusicNowPlayingScript.currentPlaying()
    let preferredTrackID = resolvedTrackID(
      title: system.title,
      artist: system.artist,
      systemTrackID: system.trackID,
      scriptResult: scripted
    )
    applyTrackUpdate(
      title: system.title,
      artist: system.artist,
      paused: system.isPaused,
      trackID: preferredTrackID
    )
  }

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
    periodicRefreshTask?.cancel()
    if let observer {
      DistributedNotificationCenter.default().removeObserver(observer)
    }
  }

  private func handleMusicNotification(_ note: Notification) {
    let info = note.userInfo
    let state = info?["Player State"] as? String ?? ""
    let rawTitle = ((info?["Name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let rawArtist = ((info?["Artist"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let t = rawTitle.isEmpty ? title : rawTitle
    let a = rawArtist.isEmpty ? artist : rawArtist
    let scripted = MusicNowPlayingScript.currentPlaying()
    let preferredTrackID = resolvedTrackID(
      title: t,
      artist: a,
      systemTrackID: "",
      scriptResult: scripted
    )
    if state == "Playing" {
      applyTrackUpdate(title: t, artist: a, paused: false, trackID: preferredTrackID)
    } else if state == "Paused" {
      applyTrackUpdate(title: t, artist: a, paused: true, trackID: preferredTrackID)
    } else {
      applyTrackUpdate(title: "—", artist: "—", paused: false, trackID: "")
    }
  }

  private func startPeriodicRefresh() {
    periodicRefreshTask?.cancel()
    periodicRefreshTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(5))
        guard let self else { return }
        await self.refreshFromSystem()
      }
    }
  }

  private func applyTrackUpdate(title newTitle: String, artist newArtist: String, paused newPaused: Bool, trackID newTrackID: String) {
    let normalizedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : newTitle
    let normalizedArtist = newArtist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : newArtist
    let normalizedTrackID = newTrackID.trimmingCharacters(in: .whitespacesAndNewlines)
    let trackChanged = normalizedTitle != title || normalizedArtist != artist
    let trackIDChanged = !trackChanged && !normalizedTrackID.isEmpty && normalizedTrackID != trackID
    let pauseChanged = newPaused != isPaused

    if !trackChanged && !pauseChanged && !trackIDChanged {
      return
    }

    title = normalizedTitle
    artist = normalizedArtist
    if trackChanged || trackIDChanged {
      trackID = normalizedTrackID
    }
    isPaused = newPaused
    if trackChanged {
      artworkURL = ""
      onTrackChanged?(normalizedTitle, normalizedArtist, "", trackID)
      if normalizedTitle != "—" {
        Task {
          let details = await Self.fetchTrackDetails(
            title: normalizedTitle,
            artist: normalizedArtist,
            fallbackTrackID: trackID
          )
          guard self.title == normalizedTitle, self.artist == normalizedArtist else { return }
          artworkURL = details.artworkURL
          if !details.trackID.isEmpty {
            trackID = details.trackID
          }
          onTrackChanged?(normalizedTitle, normalizedArtist, details.artworkURL, trackID)
        }
      }
    }
    if pauseChanged && !trackChanged {
      onTrackChanged?(normalizedTitle, normalizedArtist, artworkURL, trackID)
    }
    if trackIDChanged && !trackChanged && !pauseChanged {
      onTrackChanged?(normalizedTitle, normalizedArtist, artworkURL, trackID)
    }
  }

  private static func fetchTrackDetails(title: String, artist: String, fallbackTrackID: String) async -> (artworkURL: String, trackID: String) {
    let term = "\(title) \(artist)"
    guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
          let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=1")
    else { return ("", fallbackTrackID) }
    guard let (data, _) = try? await URLSession.shared.data(from: url) else { return ("", fallbackTrackID) }
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let results = json["results"] as? [[String: Any]],
          let first = results.first
    else { return ("", fallbackTrackID) }

    let artwork = (first["artworkUrl100"] as? String)?
      .replacingOccurrences(of: "100x100bb", with: "300x300bb") ?? ""
    let trackID = extractTrackID(from: first) ?? fallbackTrackID
    return (artwork, trackID)
  }

  private static func extractTrackID(from result: [String: Any]) -> String? {
    if let value = result["trackId"] as? NSNumber {
      return value.stringValue
    }
    if let value = result["trackId"] as? String {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    return nil
  }

  private func resolvedTrackID(
    title: String,
    artist: String,
    systemTrackID: String,
    scriptResult: (title: String, artist: String, isPaused: Bool, trackID: String)?
  ) -> String {
    let normalizedSystem = systemTrackID.trimmingCharacters(in: .whitespacesAndNewlines)
    if !normalizedSystem.isEmpty {
      return normalizedSystem
    }
    guard let scriptResult else { return "" }
    let sameTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      == scriptResult.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let sameArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      == scriptResult.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard sameTitle && sameArtist else { return "" }
    return scriptResult.trackID.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
