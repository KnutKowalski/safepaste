import AppKit
import ApplicationServices
import CoreGraphics

/// Fix für den Maccy Accessibility.check()-No-Op: Ohne Berechtigung wird
/// der Nutzer jetzt per Systemdialog zur Freigabe aufgefordert.
enum PasteSupport {
  static func isTrusted() -> Bool {
    AXIsProcessTrusted()
  }

  @discardableResult
  static func promptIfNotTrusted() -> Bool {
    if isTrusted() { return true }
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    return false
  }

  /// Simuliert ⌘V (wie Maccy, ohne Layout-Sonderfälle – bewusst schlank).
  static func paste() {
    let source = CGEventSource(stateID: .combinedSessionState)
    let vCode = CGKeyCode(9) // ANSI V
    let flags = CGEventFlags.maskCommand
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: vCode, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: vCode, keyDown: false) else {
      return
    }
    down.flags = flags
    up.flags = flags
    down.post(tap: .cgSessionEventTap)
    up.post(tap: .cgSessionEventTap)
  }
}
