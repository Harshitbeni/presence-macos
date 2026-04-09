import AppKit
import SwiftUI

// MARK: - Peer State

enum PeerState: Equatable {
  case offline
  case online
  case playing(artworkURL: String)
  case connected(artworkURL: String)
}

// MARK: - Avatar Color Helper

private func avatarColor(for name: String) -> Color {
  let colors: [Character: Color] = [
    "A": Color(red: 0.68, green: 0.85, blue: 1.00),
    "B": Color(red: 0.75, green: 0.90, blue: 0.75),
    "C": Color(red: 1.00, green: 0.80, blue: 0.70),
    "D": Color(red: 0.85, green: 0.75, blue: 1.00),
    "E": Color(red: 1.00, green: 0.85, blue: 0.70),
    "F": Color(red: 0.70, green: 0.90, blue: 0.90),
    "G": Color(red: 1.00, green: 0.75, blue: 0.80),
    "H": Color(red: 0.80, green: 0.90, blue: 0.68),
    "I": Color(red: 0.75, green: 0.85, blue: 1.00),
    "J": Color(red: 1.00, green: 0.70, blue: 0.70),
    "K": Color(red: 0.80, green: 0.75, blue: 1.00),
    "L": Color(red: 0.70, green: 0.90, blue: 0.80),
    "M": Color(red: 0.90, green: 0.75, blue: 1.00),
    "N": Color(red: 1.00, green: 0.90, blue: 0.65),
    "O": Color(red: 0.70, green: 0.85, blue: 0.95),
    "P": Color(red: 1.00, green: 0.78, blue: 0.85),
    "Q": Color(red: 0.78, green: 0.88, blue: 0.78),
    "R": Color(red: 1.00, green: 0.72, blue: 0.72),
    "S": Color(red: 0.72, green: 0.88, blue: 1.00),
    "T": Color(red: 0.88, green: 1.00, blue: 0.80),
    "U": Color(red: 0.80, green: 0.72, blue: 1.00),
    "V": Color(red: 1.00, green: 0.85, blue: 0.72),
    "W": Color(red: 0.72, green: 0.95, blue: 0.90),
    "X": Color(red: 0.95, green: 0.80, blue: 0.72),
    "Y": Color(red: 1.00, green: 0.95, blue: 0.65),
    "Z": Color(red: 0.80, green: 0.80, blue: 0.80),
  ]
  let key = (name.first?.uppercased().first) ?? "?"
  return colors[key] ?? Color(red: 0.82, green: 0.82, blue: 0.88)
}

// MARK: - Peer Avatar View

struct PeerAvatarView: View {
  let name: String
  let state: PeerState

  private let avatarSize: CGFloat = 58
  private let dotSize: CGFloat = 16
  private let badgeSize: CGFloat = 26
  private let ringWidth: CGFloat = 2.5

  var body: some View {
    ZStack {
      // Avatar circle
      Circle()
        .fill(avatarColor(for: name))
        .frame(width: avatarSize, height: avatarSize)

      Text(String(name.first ?? "?").uppercased())
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(.white)
    }
    .grayscale(state == .offline ? 1.0 : 0.0)
    .opacity(state == .offline ? 0.6 : 1.0)
    .animation(.easeInOut(duration: 0.3), value: state == .offline)
    // Solid and dashed ring treatments for active friend states.
    .overlay {
      if case .playing = state {
        Circle()
          .strokeBorder(Color.red.opacity(0.85), lineWidth: ringWidth)
          .frame(width: avatarSize + 6, height: avatarSize + 6)
      }
      if case .connected = state {
        Circle()
          .strokeBorder(style: StrokeStyle(lineWidth: ringWidth, dash: [6, 6]))
          .foregroundStyle(Color.red.opacity(0.85))
          .frame(width: avatarSize + 12, height: avatarSize + 12)
      }
    }
    // Badge in bottom-right corner
    .overlay(alignment: .bottomTrailing) {
      badgeView
    }
    // Extra padding so the badge has room to overflow
    .padding(.bottom, 6)
    .padding(.trailing, 6)
  }

  @ViewBuilder
  private var badgeView: some View {
    switch state {
    case .offline:
      EmptyView()

    case .online:
      Circle()
        .fill(Color.green)
        .frame(width: dotSize, height: dotSize)
        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
        .offset(x: 4, y: 4)

    case .playing(let url):
      albumBadge(url: url)
        .offset(x: 4, y: 4)

    case .connected(let url):
      albumBadge(url: url)
        .offset(x: 4, y: 4)
    }
  }

  @ViewBuilder
  private func albumBadge(url: String) -> some View {
    Group {
      if let imageURL = URL(string: url), !url.isEmpty {
        AsyncImage(url: imageURL) { image in
          image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
          RoundedRectangle(cornerRadius: 4)
            .fill(Color.secondary.opacity(0.3))
        }
      } else {
        RoundedRectangle(cornerRadius: 4)
          .fill(Color.secondary.opacity(0.3))
      }
    }
    .frame(width: badgeSize, height: badgeSize)
    .clipShape(RoundedRectangle(cornerRadius: 4))
    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white, lineWidth: 1.5))
  }
}

// MARK: - Content View

struct ContentView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Bindable var nowPlaying: NowPlayingStore
  @Bindable var realtime: PresenceRealtime
  @Bindable var profile: UserProfile
  @State private var tuneInMessage: String?
  @State private var tuneInBusy = false
  @State private var tunedInPeerId: String?

  private let friendColumns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 5)

  var body: some View {
    ZStack {
      VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(panelTint)

      VStack(alignment: .leading, spacing: 18) {
        header

        if realtime.isStreamingEnabled {
          Group {
            if realtime.friends.isEmpty {
              EmptyFriendsState()
            } else {
              LazyVGrid(columns: friendColumns, alignment: .leading, spacing: 14) {
                ForEach(realtime.friends, id: \.userId) { friend in
                  PeerAvatarView(name: displayName(for: friend), state: peerState(for: friend))
                    .help(displayName(for: friend))
                    .onTapGesture {
                      tuneInToFriend(friend)
                    }
                }
              }
            }
          }
          .transition(.opacity.combined(with: .move(edge: .top)))
        }

        Rectangle()
          .fill(Color.primary.opacity(0.12))
          .frame(height: 1)

        VStack(alignment: .leading, spacing: 10) {
          NowPlayingRow(
            title: nowPlaying.title,
            artist: nowPlaying.artist,
            artworkURL: nowPlaying.artworkURL
          )
          .opacity(nowPlaying.isPaused ? 0.6 : 1.0)
          .animation(.easeInOut(duration: 0.3), value: nowPlaying.isPaused)

          if let tuneInMessage {
            Text(tuneInMessage)
              .font(.caption)
              .foregroundStyle(
                tuneInMessage.contains("denied") || tuneInMessage.contains("No ") ? .red : .secondary
              )
          }
        }
      }
      .padding(22)
      .frame(width: 380, alignment: .topLeading)
    }
    .overlay(
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
    )
    .animation(.easeInOut(duration: 0.2), value: realtime.isStreamingEnabled)
    .onChange(of: realtime.friends.map(\.userId)) { _, ids in
      if let tunedInPeerId, !ids.contains(tunedInPeerId) {
        self.tunedInPeerId = nil
      }
    }
  }

  private var header: some View {
    HStack {
      Text("Beta Testers")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
          Capsule(style: .continuous)
            .fill(Color.primary.opacity(0.08))
        )

      Spacer()

      Toggle("", isOn: streamingBinding)
        .toggleStyle(.switch)
        .labelsHidden()
        .help("Pause/Resume Presence streaming")
    }
  }

  private var streamingBinding: Binding<Bool> {
    Binding(
      get: { realtime.isStreamingEnabled },
      set: { enabled in
        Task { await realtime.setStreamingEnabled(enabled) }
      }
    )
  }

  private func displayName(for friend: PresencePayload) -> String {
    friend.displayName.isEmpty ? "Friend" : friend.displayName
  }

  private func peerState(for friend: PresencePayload) -> PeerState {
    let hasTrack = !friend.title.trimmingCharacters(in: .whitespaces).isEmpty && friend.title != "—"
    if !hasTrack { return .online }
    if tunedInPeerId == friend.userId {
      return .connected(artworkURL: friend.artworkURL)
    }
    return .playing(artworkURL: friend.artworkURL)
  }

  private func tuneInToFriend(_ friend: PresencePayload) {
    let state = peerState(for: friend)
    guard case .playing = state else { return }
    guard !tuneInBusy else { return }

    tuneInBusy = true
    tuneInMessage = nil
    Task {
      let result = await TuneInService.tuneIn(
        peerTitle: friend.title,
        peerArtist: friend.artist
      )
      tuneInMessage = result
      tuneInBusy = false
      if result == nil {
        tunedInPeerId = friend.userId
      }
    }
  }

  private var panelTint: Color {
    if colorScheme == .dark {
      return Color(red: 0.18, green: 0.40, blue: 0.56).opacity(0.52)
    }
    return Color(red: 0.39, green: 0.71, blue: 0.92).opacity(0.48)
  }
}

// MARK: - Now Playing Row

struct NowPlayingRow: View {
  let title: String
  let artist: String
  let artworkURL: String

  var body: some View {
    HStack(spacing: 14) {
      Group {
        if let url = URL(string: artworkURL), !artworkURL.isEmpty {
          AsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
          } placeholder: {
            artworkPlaceholder
          }
        } else {
          artworkPlaceholder
        }
      }
      .frame(width: 48, height: 48)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
        Text(artist)
          .font(.system(size: 12, weight: .regular))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
    }
  }

  private var artworkPlaceholder: some View {
    RoundedRectangle(cornerRadius: 12, style: .continuous)
      .fill(Color.primary.opacity(0.12))
      .overlay(
        Image(systemName: "music.note")
          .foregroundStyle(.secondary)
      )
  }
}

struct EmptyFriendsState: View {
  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "person.3.sequence")
        .font(.system(size: 18, weight: .regular))
        .foregroundStyle(.secondary)
      Text("No one is online right now")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
  }
}

// MARK: - macOS Blur

struct VisualEffectBlur: NSViewRepresentable {
  var material: NSVisualEffectView.Material
  var blendingMode: NSVisualEffectView.BlendingMode

  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = material
    view.blendingMode = blendingMode
    view.state = .active
    return view
  }

  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
    nsView.material = material
    nsView.blendingMode = blendingMode
    nsView.state = .active
  }
}
