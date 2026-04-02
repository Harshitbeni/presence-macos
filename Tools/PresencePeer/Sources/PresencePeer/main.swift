import Foundation
import Supabase

private struct PresencePayload: Codable, Equatable, Sendable {
  var userId: String
  var title: String
  var artist: String
  var updatedAt: Int64
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

      let channel = supabase.channel("v01")
      _ = channel.onPresenceChange { action in
        let joinKeys = action.joins.keys.joined(separator: ", ")
        let leaveKeys = action.leaves.keys.joined(separator: ", ")
        print("[presence] joins: [\(joinKeys)] leaves: [\(leaveKeys)]")
        for (key, presence) in action.joins {
          if let decoded = try? presence.decodeState(as: PresencePayload.self) {
            print("  \(key): \(decoded.title) — \(decoded.artist) (userId=\(decoded.userId))")
          }
        }
      }

      try await channel.subscribeWithError()
      try await channel.track(
        PresencePayload(
          userId: userId,
          title: "Smoke Test Track",
          artist: "PresencePeer CLI",
          updatedAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
      )
      print("[PresencePeer] tracking on channel v01; Ctrl+C to exit")

      while true {
        try await Task.sleep(for: .seconds(60))
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
