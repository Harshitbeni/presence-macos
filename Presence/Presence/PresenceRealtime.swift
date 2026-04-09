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
  private var heartbeatTask: Task<Void, Never>?

  // Latest local track — kept so the heartbeat can re-broadcast current state.
  private var currentTitle: String = "—"
  private var currentArtist: String = "—"
  private var currentArtworkURL: String = ""

  private let profile: UserProfile

  var connectionState: String = "Starting…"
  var peerDisplayName: String = ""
  var peerImessageContact: String = ""
  var peerTitle: String = ""
  var peerArtist: String = ""
  var peerArtworkURL: String = ""
  var peerOnline: Bool = false
  var lastError: String?

  init(profile: UserProfile) {
    self.profile = profile
  }

  func start() async {
    guard !subscribed else { return }
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

      try await ch.track(makePayload())
      startHeartbeat()
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

  // Re-tracks presence every 25 seconds so peers don't lose you if the
  // Realtime connection drops and silently reconnects.
  private func startHeartbeat() {
    heartbeatTask?.cancel()
    heartbeatTask = Task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(25))
        guard !Task.isCancelled, subscribed, let ch = channel else { continue }
        try? await ch.track(makePayload())
      }
    }
  }

  private func makePayload() -> PresencePayload {
    PresencePayload(
      userId: localUserId,
      displayName: profile.displayName,
      imessageContact: profile.imessageContact,
      title: currentTitle,
      artist: currentArtist,
      artworkURL: currentArtworkURL,
      updatedAt: Int64(Date().timeIntervalSince1970 * 1000)
    )
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
      peerDisplayName = ""
      peerImessageContact = ""
      peerTitle = ""
      peerArtist = ""
      peerArtworkURL = ""
      return
    }
    peerOnline = true
    peerDisplayName = peer.displayName
    peerImessageContact = peer.imessageContact
    peerTitle = peer.title
    peerArtist = peer.artist
    peerArtworkURL = peer.artworkURL
  }

  func updateLocalTrack(title: String, artist: String, artworkURL: String) async {
    currentTitle = title
    currentArtist = artist
    currentArtworkURL = artworkURL
    guard subscribed, let ch = channel else { return }
    do {
      try await ch.track(makePayload())
    } catch {
      lastError = String(describing: error)
    }
  }
}
