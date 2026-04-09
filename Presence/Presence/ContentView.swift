import AppKit
import SwiftUI

struct ContentView: View {
  @Bindable var nowPlaying: NowPlayingStore
  @Bindable var realtime: PresenceRealtime
  @Bindable var profile: UserProfile
  @State private var tuneInMessage: String?
  @State private var tuneInBusy = false

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

      Divider()

      // — Peer's track —
      if realtime.peerOnline {
        HStack(alignment: .firstTextBaseline) {
          Text(realtime.peerDisplayName.isEmpty ? "Friend" : realtime.peerDisplayName)
            .font(.headline)
          Spacer()
          if !realtime.peerImessageContact.isEmpty {
            Button {
              if let url = URL(string: "imessage:\(realtime.peerImessageContact)") {
                NSWorkspace.shared.open(url)
              }
            } label: {
              Label(realtime.peerImessageContact, systemImage: "message.fill")
                .font(.caption)
                .lineLimit(1)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
          }
        }
        TrackRow(
          title: realtime.peerTitle.isEmpty ? "—" : realtime.peerTitle,
          artist: realtime.peerArtist.isEmpty ? "—" : realtime.peerArtist,
          artworkURL: realtime.peerArtworkURL
        ) {
          guard !tuneInBusy else { return }
          tuneInBusy = true
          tuneInMessage = nil
          Task {
            tuneInMessage = await TuneInService.tuneIn(
              peerTitle: realtime.peerTitle,
              peerArtist: realtime.peerArtist
            )
            tuneInBusy = false
          }
        }
      } else {
        Text("Remote")
          .font(.headline)
        Text("No peer online")
          .foregroundStyle(.secondary)
      }

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
          .foregroundStyle(tuneInMessage.contains("denied") || tuneInMessage.contains("No ") ? .red : .primary)
      }

      Spacer(minLength: 8)

      Button("Quit Presence") {
        NSApp.stop(nil)
      }
      .keyboardShortcut("q", modifiers: .command)
    }
    .padding(16)
    .frame(width: 300, height: 400, alignment: .topLeading)
  }
}

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
    .help("Click to open in Apple Music")
  }

  private var artworkPlaceholder: some View {
    RoundedRectangle(cornerRadius: 4)
      .fill(Color.secondary.opacity(0.2))
  }
}
