import Foundation
import Supabase

/// Mirrors the app's PresencePayload — matches the `user_tracks` table columns.
private struct TrackRow: Codable, Sendable {
  var id: String
  var displayName: String
  var imessageContact: String
  var title: String
  var artist: String
  var artworkURL: String
  var trackID: String
  var isPaused: Bool
  var updatedAt: String
  var lastSeenAt: String

  private enum CodingKeys: String, CodingKey {
    case id
    case displayName = "display_name"
    case imessageContact = "imessage_contact"
    case title
    case artist
    case artworkURL = "artwork_url"
    case trackID = "track_id"
    case isPaused = "is_paused"
    case updatedAt = "updated_at"
    case lastSeenAt = "last_seen_at"
  }
}

@main
enum PresencePeer {
  static func main() async {
    let env = ProcessInfo.processInfo.environment
    guard let urlString = env["SUPABASE_URL"], !urlString.isEmpty,
          let key = env["SUPABASE_ANON_KEY"], !key.isEmpty,
          let url = URL(string: urlString)
    else {
      fputs("Set SUPABASE_URL and SUPABASE_ANON_KEY (same as Xcode scheme).\n", stderr)
      exit(1)
    }

    let supabase = SupabaseClient(
      supabaseURL: url,
      supabaseKey: key,
      options: SupabaseClientOptions(
        auth: .init(emitLocalSessionAsInitialSession: true)
      )
    )

    do {
      let session = try await supabase.auth.signInAnonymously()
      let userId = session.user.id.uuidString
      print("[PresencePeer] anonymous user \(userId)")

      // Insert our row into user_tracks.
      let now = ISO8601DateFormatter().string(from: Date())
      let row: [String: String] = [
        "id": userId,
        "display_name": "PresencePeer CLI",
        "imessage_contact": "",
        "title": "Smoke Test Track",
        "artist": "PresencePeer CLI",
        "artwork_url": "",
        "track_id": "",
        "is_paused": "false",
        "updated_at": now,
        "last_seen_at": now,
      ]
      try await supabase.from("user_tracks")
        .upsert(row, onConflict: "id")
        .execute()
      print("[PresencePeer] row inserted into user_tracks")

      // Load existing peers.
      let existing: PostgrestResponse<[TrackRow]> = try await supabase.from("user_tracks")
        .select()
        .execute()
      print("[PresencePeer] current rows in user_tracks:")
      for peer in existing.value {
        let marker = peer.id == userId ? " (me)" : ""
        print("  \(peer.displayName): \(peer.title) — \(peer.artist)\(marker)")
      }

      // Subscribe to live changes.
      let channel = supabase.channel("peer-watcher")
      let decoder = JSONDecoder()
      decoder.keyDecodingStrategy = .convertFromSnakeCase

      _ = channel.onPostgresChange(
        AnyAction.self,
        schema: "public",
        table: "user_tracks"
      ) { action in
        switch action {
        case .insert(let a):
          if let row = try? a.decodeRecord(as: TrackRow.self, decoder: decoder) {
            print("[INSERT] \(row.displayName): \(row.title) — \(row.artist)")
          }
        case .update(let a):
          if let row = try? a.decodeRecord(as: TrackRow.self, decoder: decoder) {
            print("[UPDATE] \(row.displayName): \(row.title) — \(row.artist)")
          }
        case .delete(let a):
          if let row = try? a.decodeOldRecord(as: TrackRow.self, decoder: decoder) {
            print("[DELETE] \(row.displayName)")
          }
        }
      }

      try await channel.subscribeWithError()
      print("[PresencePeer] listening for changes on user_tracks; Ctrl+C to exit")

      // Heartbeat: keep last_seen_at fresh.
      while true {
        try await Task.sleep(for: .seconds(30))
        let heartbeatNow = ISO8601DateFormatter().string(from: Date())
        try await supabase.from("user_tracks")
          .update(["last_seen_at": heartbeatNow])
          .eq("id", value: userId)
          .execute()
        print("[heartbeat] last_seen_at updated")
      }
    } catch {
      let text = String(describing: error)
      if text.contains("anonymous_provider_disabled") || text.contains("Anonymous sign-ins are disabled") {
        fputs(
          "Enable Anonymous sign-ins: Supabase Dashboard → Authentication → Providers → Anonymous.\n",
          stderr
        )
      }
      fputs("PresencePeer error: \(error)\n", stderr)
      exit(1)
    }
  }
}
