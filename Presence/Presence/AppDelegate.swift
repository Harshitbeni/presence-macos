import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem?
  private var panel: NSPanel?
  private let nowPlaying = NowPlayingStore()
  private lazy var presenceRealtime = PresenceRealtime()

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    setupStatusItem()
    nowPlaying.onTrackChanged = { [weak self] title, artist, artworkURL in
      Task { await self?.presenceRealtime.updateLocalTrack(title: title, artist: artist, artworkURL: artworkURL) }
    }
    Task { await presenceRealtime.start() }
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
      let view = ContentView(nowPlaying: nowPlaying, realtime: presenceRealtime)
      let host = NSHostingController<ContentView>(rootView: view)
      let p = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 440),
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
