import Foundation

/// Mirrors one row in the `user_tracks` table.
struct PresencePayload: Codable, Equatable, Sendable, Identifiable {
  var id: String               // auth.uid()
  var displayName: String
  var imessageContact: String
  var title: String
  var artist: String
  var artworkURL: String
  var trackID: String
  var isPaused: Bool
  var updatedAt: String        // ISO-8601 timestamptz from Postgres
  var lastSeenAt: String       // ISO-8601 timestamptz from Postgres

  /// True when the peer was seen within the last 60 seconds.
  var isOnline: Bool {
    guard let date = Self.parseDate(lastSeenAt) else { return false }
    return Date().timeIntervalSince(date) < 60
  }

  /// True when the peer is actively playing a track (not paused, has a title).
  var isPlaying: Bool {
    !isPaused && !title.isEmpty && title != "—"
  }

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

  private static let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  private static func parseDate(_ string: String) -> Date? {
    isoFormatter.date(from: string)
  }
}
