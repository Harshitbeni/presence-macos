import Foundation

struct PresencePayload: Codable, Equatable, Sendable {
  var userId: String
  var title: String
  var artist: String
  var artworkURL: String
  var updatedAt: Int64
}
