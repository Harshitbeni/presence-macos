import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem?
  private var panel: NSPanel?
  private var signUpWindow: NSWindow?
  private let profile = UserProfile()
  private let nowPlaying = NowPlayingStore()
  private lazy var presenceRealtime = PresenceRealtime(profile: profile)

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    setupStatusItem()
    nowPlaying.onTrackChanged = { [weak self] title, artist, artworkURL in
      Task { await self?.presenceRealtime.updateLocalTrack(title: title, artist: artist, artworkURL: artworkURL) }
    }
    observeProfileCompletion()
    if profile.isComplete {
      Task { await presenceRealtime.start() }
    } else {
      showSignUpWindow()
    }
  }

  // Sign-up uses a real NSWindow so text fields get proper keyboard focus.
  private func showSignUpWindow() {
    guard signUpWindow == nil else { return }
    let view = SignInView(profile: profile)
    let host = NSHostingController(rootView: view)
    let w = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 340),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    w.title = ""
    w.titlebarAppearsTransparent = true
    w.isMovableByWindowBackground = true
    w.isReleasedWhenClosed = false
    w.center()
    w.contentViewController = host
    signUpWindow = w
    w.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  // Watches profile.isComplete; when sign-up finishes, closes the sign-up window
  // and opens the music panel. One-shot — re-subscribes only if profile is cleared.
  private func observeProfileCompletion() {
    withObservationTracking {
      _ = profile.isComplete
    } onChange: {
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        if self.profile.isComplete {
          self.signUpWindow?.close()
          self.signUpWindow = nil
          Task { await self.presenceRealtime.start() }
          self.togglePanel()
        } else {
          // Profile was cleared (e.g. reset) — show sign-up again.
          self.panel?.orderOut(nil)
          self.panel = nil
          self.showSignUpWindow()
          self.observeProfileCompletion()
        }
      }
    }
  }

  private func setupStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem = item
    guard let button = item.button else { return }
    button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Presence")
    button.toolTip = "Presence"
    button.target = self
    button.action = #selector(togglePanel)
  }

  @objc private func togglePanel() {
    guard let button = statusItem?.button else { return }
    if let panel, panel.isVisible {
      panel.orderOut(nil)
      return
    }
    if panel == nil {
      let view = ContentView(nowPlaying: nowPlaying, realtime: presenceRealtime, profile: profile)
      let host = NSHostingController<ContentView>(rootView: view)
      let p = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
        styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
        backing: .buffered,
        defer: false
      )
      p.isFloatingPanel = true
      p.level = .popUpMenu
      p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      p.isMovable = false
      p.hidesOnDeactivate = false
      p.hasShadow = true
      p.isOpaque = false
      p.backgroundColor = .clear
      p.contentViewController = host
      panel = p
    }
    guard let panel, let window = button.window else { return }
    let buttonRect = window.frame
    let panelSize = panel.frame.size
    let x = buttonRect.midX - panelSize.width / 2
    let y = buttonRect.minY - panelSize.height - 4
    panel.setFrameOrigin(NSPoint(x: x, y: y))
    panel.orderFrontRegardless()
  }
}
