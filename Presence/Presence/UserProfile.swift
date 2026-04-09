import Foundation

@Observable
final class UserProfile {
  private static let nameKey    = "presence.user.displayName"
  private static let contactKey = "presence.user.imessageContact"

  var displayName: String {
    didSet { UserDefaults.standard.set(displayName, forKey: Self.nameKey) }
  }
  var imessageContact: String {
    didSet { UserDefaults.standard.set(imessageContact, forKey: Self.contactKey) }
  }

  var isComplete: Bool {
    !displayName.trimmingCharacters(in: .whitespaces).isEmpty &&
    !imessageContact.trimmingCharacters(in: .whitespaces).isEmpty
  }

  init() {
    displayName     = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
    imessageContact = UserDefaults.standard.string(forKey: Self.contactKey) ?? ""
  }
}
