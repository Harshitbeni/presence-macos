import Foundation
import Supabase

@MainActor
@Observable
final class PresenceRealtime {
  private let channelName = "v01"
  private var channel: RealtimeChannelV2?
  private var presenceSubscription: RealtimeSubscription?
  private var localUserId: String = ""
  private var presenceMap: [String: PresencePayload] = [:]
  private var subscribed = false

  var connectionState: String = "Starting…"
  var peerTitle: String = ""
  var peerArtist: String = ""
  var peerArtworkURL: String = ""
  var peerOnline: Bool = false
  var lastError: String?

  init() {}

  func start() async {
    guard let (url, anonKey) = SupabaseConfig.resolve() else {
      connectionState = "Needs config"
      lastError = SupabaseConfig.configurationHint
      return
    }

    // Avoids supabase-swift calling reportIssue() on initial session (pauses Xcode debugger).
    let client = SupabaseClient(
      supabaseURL: url,
      supabaseKey: anonKey,
      options: SupabaseClientOptions(
        auth: .init(emitLocalSessionAsInitialSession: true)
      )
    )

    connectionState = "Signing in…"
    do {
      _ = try await client.auth.signInAnonymously()
      let session = try await client.auth.session
      localUserId = session.user.id.uuidString

      let ch = client.channel(channelName)

      presenceSubscription = ch.onPresenceChange { [weak self] action in
        Task { @MainActor in
          self?.applyPresenceDiff(action)
        }
      }

      try await ch.subscribeWithError()
      channel = ch
      subscribed = true
      connectionState = "Connected"

      let initial = PresencePayload(
        userId: localUserId,
        title: "—",
        artist: "—",
        artworkURL: "",
        updatedAt: Int64(Date().timeIntervalSince1970 * 1000)
      )
      try await ch.track(initial)
    } catch {
      subscribed = false
      connectionState = "Error"
      let text = String(describing: error)
      if text.contains("anonymous_provider_disabled") || text.contains("Anonymous sign-ins are disabled") {
        lastError =
          "Supabase: enable Anonymous sign-ins (Dashboard → Authentication → Providers → Anonymous)."
      } else {
        lastError = text
      }
    }
  }

  private func applyPresenceDiff(_ action: any PresenceAction) {
    for (key, presence) in action.joins {
      if let decoded = try? presence.decodeState(as: PresencePayload.self) {
        presenceMap[key] = decoded
      }
    }
    for key in action.leaves.keys {
      presenceMap.removeValue(forKey: key)
    }
    pickPeer()
  }

  private func pickPeer() {
    let others = presenceMap.values.filter { $0.userId != localUserId && !$0.userId.isEmpty }
    guard let peer = others.first else {
      peerOnline = false
      peerTitle = ""
      peerArtist = ""
      peerArtworkURL = ""
      return
    }
    peerOnline = true
    peerTitle = peer.title
    peerArtist = peer.artist
    peerArtworkURL = peer.artworkURL
  }

  func updateLocalTrack(title: String, artist: String, artworkURL: String) async {
    guard subscribed, let ch = channel else { return }
    let payload = PresencePayload(
      userId: localUserId,
      title: title,
      artist: artist,
      artworkURL: artworkURL,
      updatedAt: Int64(Date().timeIntervalSince1970 * 1000)
    )
    do {
      try await ch.track(payload)
    } catch {
      lastError = String(describing: error)
    }
  }
}
