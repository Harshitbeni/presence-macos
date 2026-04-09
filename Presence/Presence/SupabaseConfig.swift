import Foundation

enum SupabaseConfig {
  /// Resolves credentials from: (1) process environment, (2) `Secrets.plist` in the bundle, (3) Application Support `Presence/Supabase.plist`.
  static func resolve() -> (url: URL, anonKey: String)? {
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
