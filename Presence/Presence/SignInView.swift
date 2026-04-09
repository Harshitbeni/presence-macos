import SwiftUI

struct SignInView: View {
  @Bindable var profile: UserProfile

  @State private var name: String = ""
  @State private var contact: String = ""

  private var canContinue: Bool {
    !name.trimmingCharacters(in: .whitespaces).isEmpty &&
    !contact.trimmingCharacters(in: .whitespaces).isEmpty
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Welcome to Presence")
          .font(.headline)
        Text("Share what you're listening to with people you care about.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Your name")
            .font(.caption)
            .foregroundStyle(.secondary)
          TextField("e.g. Harshit", text: $name)
            .textFieldStyle(.roundedBorder)
        }

        VStack(alignment: .leading, spacing: 4) {
          Text("iMessage contact")
            .font(.caption)
            .foregroundStyle(.secondary)
          TextField("email or phone number", text: $contact)
            .textFieldStyle(.roundedBorder)
          Text("How friends can reach you on iMessage")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }

      Button("Continue") {
        profile.displayName     = name.trimmingCharacters(in: .whitespaces)
        profile.imessageContact = contact.trimmingCharacters(in: .whitespaces)
      }
      .buttonStyle(.borderedProminent)
      .disabled(!canContinue)
      .frame(maxWidth: .infinity)

      Spacer(minLength: 0)
    }
    .padding(20)
    .padding(.top, 8) // extra clearance for transparent title bar
    .frame(width: 300, height: 320, alignment: .topLeading)
  }
}
