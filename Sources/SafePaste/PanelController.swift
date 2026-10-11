import AppKit
import Carbon.HIToolbox
import SwiftUI

extension Notification.Name {
  static let safepasteHotkey = Notification.Name("safepasteHotkey")
}

final class ActivePanel: NSPanel {
  override var canBecomeKey: Bool { true }
}

final class PanelController: NSObject, NSWindowDelegate {
  static let shared = PanelController()

  let viewModel = HistoryViewModel()

  private var panel: NSPanel?
  private var statusItem: NSStatusItem?
  private var keyMonitor: Any?
  private var hotKeyRef: EventHotKeyRef?
  private var hotKeyHandler: EventHandlerRef?
  private var hotkeyObserver: NSObjectProtocol?

  func setup() {
    installStatusItem()
    registerHotKey()
    installKeyMonitor()
    NotificationCenter.default.addObserver(
      self, selector: #selector(togglePanel), name: .safepasteHotkey, object: nil
    )
  }

  // MARK: - Menüleisten-Symbol

  private func installStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = item.button {
      button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "SafePaste")
      button.action = #selector(togglePanel)
      button.target = self
    }
    statusItem = item
  }

  // MARK: - Panel

  @objc func togglePanel() {
    if let panel, panel.isVisible {
      closePanel()
    } else {
      openPanel()
    }
  }

  private func openPanel() {
    let p = panel ?? makePanel()
    panel = p
    viewModel.refresh()

    if p.frame.origin == .zero, let screen = NSScreen.main {
      let visible = screen.visibleFrame
      let origin = NSPoint(
        x: visible.midX - p.frame.width / 2,
        y: visible.midY - p.frame.height / 2
      )
      p.setFrameOrigin(origin)
    }
    NSApp.activate(ignoringOtherApps: true)
    p.makeKeyAndOrderFront(nil)
  }

  func closePanel() {
    panel?.orderOut(nil)
    viewModel.search = ""
  }

  private func makePanel() -> NSPanel {
    let p = ActivePanel(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
      styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    p.isFloatingPanel = true
    p.level = .statusBar
    p.titleVisibility = .hidden
    p.titlebarAppearsTransparent = true
    p.isMovableByWindowBackground = true
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    p.standardWindowButton(.closeButton)?.isHidden = true
    p.standardWindowButton(.miniaturizeButton)?.isHidden = true
    p.standardWindowButton(.zoomButton)?.isHidden = true
    p.contentView = NSHostingView(rootView: PanelView(viewModel: viewModel))
    p.delegate = self
    return p
  }

  func windowDidResignKey(_ notification: Notification) {
    closePanel()
  }

  // MARK: - Globaler Hotkey (⇧⌘C, Carbon – keine Drittanbieter-Bibliothek)

  private func registerHotKey() {
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let handler: EventHandlerUPP = { _, event, _ in
      var hotKeyID = EventHotKeyID()
      GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
      )
      if hotKeyID.signature == FourCharCode(0x53504153) { // 'SPAS'
        NotificationCenter.default.post(name: .safepasteHotkey, object: nil)
      }
      return noErr
    }
    // 'InstallApplicationEventHandler' ist ein C-Makro (in Swift nicht verfügbar)
    // und expandiert zu exakt diesem Aufruf:
    InstallEventHandler(GetApplicationEventTarget(), handler, 1, &spec, nil, &hotKeyHandler)
    var ref: EventHotKeyRef?
    RegisterEventHotKey(
      UInt32(kVK_ANSI_C),
      UInt32(cmdKey | shiftKey),
      EventHotKeyID(signature: FourCharCode(0x53504153), id: 1),
      GetApplicationEventTarget(),
      0,
      &ref
    )
    hotKeyRef = ref
  }

  // MARK: - Tastatursteuerung im Panel

  private func installKeyMonitor() {
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, let panel = self.panel, panel.isKeyWindow else { return event }
      return self.handleKey(event) ?? event
    }
  }

  private func handleKey(_ event: NSEvent) -> NSEvent? {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

    switch event.keyCode {
    case 53: // Esc
      if viewModel.search.isEmpty {
        closePanel()
      } else {
        viewModel.search = ""
      }
      return nil
    case 126: viewModel.moveSelection(-1); return nil // ↑
    case 125: viewModel.moveSelection(1); return nil  // ↓
    case 36, 76: // ⏎ / Keypad-Enter
      let wantsPaste = flags == .option
      viewModel.copySelected(paste: wantsPaste)
      return nil
    case 51: // ⌫ – nur mit ⌘ löscht es einen Eintrag (sonst: Suchfeld-Editierung)
      if flags == .command {
        viewModel.deleteSelected()
        return nil
      }
    default:
      break
    }

    // ⌥P: Pin an/aus
    if event.charactersIgnoringModifiers == "p", flags == .option {
      viewModel.togglePinSelected()
      return nil
    }
    return event
  }
}
