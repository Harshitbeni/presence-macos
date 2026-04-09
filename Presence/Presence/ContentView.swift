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

  private let avatarSize: CGFloat = 48
  private let dotSize: CGFloat = 16
  private let badgeSize: CGFloat = 24
  private let ringWidth: CGFloat = 2

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
    // Red connected ring
    .overlay {
      if case .connected = state {
        Circle()
          .strokeBorder(Color.red, lineWidth: ringWidth)
          .frame(width: avatarSize, height: avatarSize)
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
  @Bindable var nowPlaying: NowPlayingStore
  @Bindable var realtime: PresenceRealtime
  @Bindable var profile: UserProfile
  @State private var tuneInMessage: String?
  @State private var tuneInBusy = false
  @State private var isTunedIn = false

  var peerState: PeerState {
    guard realtime.peerOnline else { return .offline }
    let hasArtwork = !realtime.peerArtworkURL.isEmpty
    if hasArtwork && isTunedIn { return .connected(artworkURL: realtime.peerArtworkURL) }
    if hasArtwork { return .playing(artworkURL: realtime.peerArtworkURL) }
    return .online
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // — Your track —
      Text(profile.displayName)
        .font(.headline)
      TrackRow(
        title: nowPlaying.title,
        artist: nowPlaying.artist,
        artworkURL: nowPlaying.artworkURL
      ) {
        guard !tuneInBusy, nowPlaying.title != "—" else { return }
        tuneInBusy = true
        tuneInMessage = nil
        Task {
          tuneInMessage = await TuneInService.tuneIn(
            peerTitle: nowPlaying.title,
            peerArtist: nowPlaying.artist
          )
          tuneInBusy = false
        }
      }
      .opacity(nowPlaying.isPaused ? 0.6 : 1.0)
      .animation(.easeInOut(duration: 0.3), value: nowPlaying.isPaused)

      Divider()

      // — Peer section —
      peerRow

      Text("Realtime: \(realtime.connectionState)")
        .font(.caption)
        .foregroundStyle(.tertiary)

      if let err = realtime.lastError {
        ScrollView {
          Text(err)
            .font(.caption)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(maxHeight: 180)
      }

      if let tuneInMessage {
        Text(tuneInMessage)
          .font(.caption)
          .foregroundStyle(
            tuneInMessage.contains("denied") || tuneInMessage.contains("No ") ? .red : .primary
          )
      }

      Spacer(minLength: 8)

      Button("Quit Presence") {
        NSApp.stop(nil)
      }
      .keyboardShortcut("q", modifiers: .command)
    }
    .padding(16)
    .frame(width: 300, height: 400, alignment: .topLeading)
    .onChange(of: realtime.peerOnline) { _, online in
      if !online { isTunedIn = false }
    }
  }

  @ViewBuilder
  private var peerRow: some View {
    let peerName = realtime.peerDisplayName.isEmpty ? "Friend" : realtime.peerDisplayName

    HStack(alignment: .center, spacing: 10) {
      PeerAvatarView(name: peerName, state: peerState)
        .onTapGesture {
          guard case .playing = peerState else { return }
          guard !tuneInBusy else { return }
          tuneInBusy = true
          tuneInMessage = nil
          Task {
            let result = await TuneInService.tuneIn(
              peerTitle: realtime.peerTitle,
              peerArtist: realtime.peerArtist
            )
            tuneInMessage = result
            tuneInBusy = false
            if result == nil { isTunedIn = true }
          }
        }

      VStack(alignment: .leading, spacing: 2) {
        // Name — tappable as iMessage link if contact exists
        if !realtime.peerImessageContact.isEmpty && realtime.peerOnline {
          Button {
            if let url = URL(string: "sms://open?addresses=\(realtime.peerImessageContact)") {
              NSWorkspace.shared.open(url)
            }
          } label: {
            Text(peerName)
              .font(.headline)
              .foregroundStyle(.blue)
          }
          .buttonStyle(.plain)
          .help("Message \(peerName)")
        } else {
          Text(peerName)
            .font(.headline)
            .foregroundStyle(realtime.peerOnline ? .primary : .secondary)
        }

        // Song info
        if realtime.peerOnline && !realtime.peerTitle.isEmpty {
          Text(realtime.peerTitle)
            .font(.subheadline)
            .lineLimit(1)
          Text(realtime.peerArtist)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        } else if !realtime.peerOnline {
          Text("Offline")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text("Online")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Spacer()
    }
  }
}

// MARK: - Track Row

struct TrackRow: View {
  let title: String
  let artist: String
  let artworkURL: String
  let onTap: () -> Void

  var body: some View {
    HStack(spacing: 10) {
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
      .frame(width: 44, height: 44)
      .clipShape(RoundedRectangle(cornerRadius: 4))

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
        Text(artist)
          .foregroundStyle(.secondary)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture(perform: onTap)
    .help("Click to tune in")
  }

  private var artworkPlaceholder: some View {
    RoundedRectangle(cornerRadius: 4)
      .fill(Color.secondary.opacity(0.2))
  }
}
