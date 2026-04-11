import Foundation
import Supabase

@MainActor
@Observable
final class PresenceSync {
  private let tableName = "user_tracks"
  private var client: SupabaseClient?
  private var channel: RealtimeChannelV2?
  private var localUserId: String = ""
  private var heartbeatTask: Task<Void, Never>?

  private let profile: UserProfile

  // Current local track state (sent to database on change).
  private var currentTitle: String = "—"
  private var currentArtist: String = "—"
  private var currentArtworkURL: String = ""
  private var currentTrackID: String = ""
  private var currentIsPaused: Bool = false

  // Public state for UI.
  var isStreamingEnabled: Bool = true
  var connectionState: String = "Starting…"
  var friends: [PresencePayload] = []
  var lastError: String?

  init(profile: UserProfile) {
    self.profile = profile
  }

  // MARK: - Lifecycle

  func start() async {
    guard isStreamingEnabled else {
      connectionState = "Paused"
      return
    }
    guard client == nil else {
      // Already running — just refresh.
      await upsertRow()
      return
    }
    guard let (url, anonKey) = SupabaseConfig.resolve() else {
      connectionState = "Needs config"
      lastError = SupabaseConfig.configurationHint
      return
    }

    let supabaseClient = SupabaseClient(
      supabaseURL: url,
      supabaseKey: anonKey,
      options: SupabaseClientOptions(
        auth: .init(emitLocalSessionAsInitialSession: true)
      )
    )
    self.client = supabaseClient

    connectionState = "Signing in…"
    do {
      _ = try await supabaseClient.auth.signInAnonymously()
      let session = try await supabaseClient.auth.session
      localUserId = session.user.id.uuidString
    } catch {
      handleError(error, context: "sign-in")
      return
    }

    // Subscribe to live changes on the table.
    let ch = supabaseClient.channel("user-tracks-changes")
    _ = ch.onPostgresChange(
      AnyAction.self,
      schema: "public",
      table: tableName
    ) { [weak self] action in
      Task { @MainActor in
        self?.handleChange(action)
      }
    }
    do {
      try await ch.subscribeWithError()
      channel = ch
    } catch {
      handleError(error, context: "subscribe")
      return
    }

    // Upsert our row and load the initial friend list.
    await upsertRow()
    await loadFriends()

    connectionState = "Connected"
    lastError = nil
    startHeartbeat()
  }

  func stop() async {
    heartbeatTask?.cancel()
    heartbeatTask = nil
    await deleteRow()
    channel = nil
    client = nil
    friends = []
  }

  // MARK: - Track Updates

  func updateLocalTrack(title: String, artist: String, artworkURL: String, trackID: String) async {
    currentTitle = title
    currentArtist = artist
    currentArtworkURL = artworkURL
    currentTrackID = trackID
    await upsertRow()
  }

  func setStreamingEnabled(_ enabled: Bool) async {
    guard enabled != isStreamingEnabled else { return }
    isStreamingEnabled = enabled
    if enabled {
      connectionState = "Reconnecting…"
      lastError = nil
      await start()
    } else {
      connectionState = "Paused"
      await stop()
    }
  }

  // MARK: - Database Operations

  private func upsertRow() async {
    guard let client, isStreamingEnabled else { return }
    let now = ISO8601DateFormatter().string(from: Date())
    let row: [String: String] = [
      "id": localUserId,
      "display_name": profile.displayName,
      "imessage_contact": profile.imessageContact,
      "title": currentTitle,
      "artist": currentArtist,
      "artwork_url": currentArtworkURL,
      "track_id": currentTrackID,
      "is_paused": currentIsPaused ? "true" : "false",
      "updated_at": now,
      "last_seen_at": now,
    ]
    do {
      try await client.from(tableName)
        .upsert(row, onConflict: "id")
        .execute()
    } catch {
      lastError = String(describing: error)
    }
  }

  private func deleteRow() async {
    guard let client else { return }
    do {
      try await client.from(tableName)
        .delete()
        .eq("id", value: localUserId)
        .execute()
    } catch {
      // Best-effort cleanup — don't surface this error.
    }
  }

  private func loadFriends() async {
    guard let client else { return }
    do {
      let response: PostgrestResponse<[PresencePayload]> = try await client.from(tableName)
        .select()
        .execute()
      friends = response.value.filter { $0.id != localUserId && $0.isOnline }
    } catch {
      lastError = String(describing: error)
    }
  }

  // MARK: - Realtime Change Handler

  private func handleChange(_ action: AnyAction) {
    switch action {
    case .insert(let insert):
      guard let peer = try? insert.decodeRecord(as: PresencePayload.self, decoder: Self.decoder) else { return }
      if peer.id == localUserId { return }
      // Add or update the friend.
      if let idx = friends.firstIndex(where: { $0.id == peer.id }) {
        friends[idx] = peer
      } else if peer.isOnline {
        friends.append(peer)
      }

    case .update(let update):
      guard let peer = try? update.decodeRecord(as: PresencePayload.self, decoder: Self.decoder) else { return }
      if peer.id == localUserId { return }
      if let idx = friends.firstIndex(where: { $0.id == peer.id }) {
        if peer.isOnline {
          friends[idx] = peer
        } else {
          friends.remove(at: idx)
        }
      } else if peer.isOnline {
        friends.append(peer)
      }

    case .delete(let delete):
      guard let old = try? delete.decodeOldRecord(as: PresencePayload.self, decoder: Self.decoder) else { return }
      friends.removeAll { $0.id == old.id }
    }
  }

  // MARK: - Heartbeat

  /// Updates `last_seen_at` every 30 seconds so peers know we're still online.
  private func startHeartbeat() {
    heartbeatTask?.cancel()
    heartbeatTask = Task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(30))
        guard !Task.isCancelled, isStreamingEnabled, client != nil else { continue }
        await touchLastSeen()
      }
    }
  }

  private func touchLastSeen() async {
    guard let client else { return }
    let now = ISO8601DateFormatter().string(from: Date())
    do {
      try await client.from(tableName)
        .update(["last_seen_at": now])
        .eq("id", value: localUserId)
        .execute()
    } catch {
      // Non-critical — next heartbeat will retry.
    }
  }

  // MARK: - Helpers

  private func handleError(_ error: Error, context: String) {
    client = nil
    channel = nil
    connectionState = "Error"
    let text = String(describing: error)
    if text.contains("anonymous_provider_disabled") || text.contains("Anonymous sign-ins are disabled") {
      lastError = "Supabase: enable Anonymous sign-ins (Dashboard → Authentication → Providers → Anonymous)."
    } else {
      lastError = text
    }
  }

  private static let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    return d
  }()
}
