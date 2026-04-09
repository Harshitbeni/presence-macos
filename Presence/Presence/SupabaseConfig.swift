import Foundation

enum SupabaseConfig {
  // ─── Fill these in ────────────────────────────────────────────────────────
  // Find both values at: supabase.com → your project → Settings → API
  // The anon key is safe to embed — it's a public key (like a Stripe publishable key).
  private static let hardcodedURL     = "https://sveuaztjopdwhdwsuyld.supabase.co"
  private static let hardcodedAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN2ZXVhenRqb3Bkd2hkd3N1eWxkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUxNjEzNjIsImV4cCI6MjA5MDczNzM2Mn0.8LPPRu7JJcdNbulefldVzqFUgdBHbxGiZhkRsAUejgs"
  // ──────────────────────────────────────────────────────────────────────────

  /// Resolves credentials from: (1) hardcoded values, (2) process environment, (3) `Secrets.plist` in the bundle, (4) Application Support `Presence/Supabase.plist`.
  static func resolve() -> (url: URL, anonKey: String)? {
    if let pair = parse(urlString: hardcodedURL, key: hardcodedAnonKey) {
      return pair
    }
    let env = ProcessInfo.processInfo.environment
    if let pair = parse(urlString: env["SUPABASE_URL"], key: env["SUPABASE_ANON_KEY"]) {
      return pair
    }
    if let pair = loadPlistDictionary(from: Bundle.main.url(forResource: "Secrets", withExtension: "plist")) {
      return pair
    }
    if let pair = loadFromApplicationSupportPlist() {
      return pair
    }
    return nil
  }

  static var configurationHint: String {
    """
    Supabase keys are missing. Fix one of these:

    1) Xcode: Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables.
       Add two rows: Name SUPABASE_URL (value = https://…supabase.co) and Name SUPABASE_ANON_KEY (value = anon key).
       If you use “Manage Schemes”, delete any duplicate “Presence” scheme that is not Shared, or ensure the duplicate has the same env vars.

    2) Application Support (works if Xcode env vars never reach the app):
       ~/Library/Containers/<YOUR_BUNDLE_ID>/Data/Library/Application Support/Presence/Supabase.plist
       Copy keys from Presence/Presence/Secrets.example.plist (SUPABASE_URL, SUPABASE_ANON_KEY).

    3) Bundle: copy Secrets.example.plist to Secrets.plist in the target folder and add to the app target.

    See Presence/ENV.example.
    """
  }

  private static func loadFromApplicationSupportPlist() -> (url: URL, anonKey: String)? {
    guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      return nil
    }
    let plistURL = base.appendingPathComponent("Presence", isDirectory: true).appendingPathComponent("Supabase.plist")
    return loadPlistDictionary(from: plistURL)
  }

  private static func loadPlistDictionary(from url: URL?) -> (url: URL, anonKey: String)? {
    guard let url,
          let data = try? Data(contentsOf: url),
          let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    else { return nil }
    return parse(
      urlString: dict["SUPABASE_URL"] as? String,
      key: dict["SUPABASE_ANON_KEY"] as? String
    )
  }

  private static func parse(urlString: String?, key: String?) -> (url: URL, anonKey: String)? {
    guard let urlString, !urlString.isEmpty,
          let key, !key.isEmpty,
          let url = URL(string: urlString)
    else { return nil }
    return (url, key)
  }
}
