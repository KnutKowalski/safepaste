import AppKit
import Combine
import Foundation

final class HistoryViewModel: ObservableObject {
  @Published var items: [DisplayItem] = []
  @Published var search: String = "" {
    didSet { clampSelection() }
  }
  @Published var selectedIndex: Int = 0

  var onDismiss: (() -> Void)?

  private let searchEngine = SearchEngine()

  // MARK: - Sichtbare Liste (Suche angewendet)

  var visible: [DisplayItem] {
    guard !search.isEmpty else { return items }
    return items.filter { searchEngine.matches(query: search, item: $0) }
  }

  private func clampSelection() {
    if selectedIndex >= visible.count {
      selectedIndex = max(0, visible.count - 1)
    }
  }

  // MARK: - Laden

  func refresh() {
    DispatchQueue.global(qos: .userInitiated).async {
      let loaded = HistoryStore.shared.loadAll() // Entschlüsselung außerhalb des Main-Threads
      DispatchQueue.main.async {
        self.items = loaded
        self.clampSelection()
      }
    }
  }

  func refreshIfVisible() {
    // Bewusst einfach: Laden ist billig (Entschlüsselung läuft im Hintergrund
    // außerhalb des Main-Threads). Ein sichtbarkeitsabhängiger Refresh brächte
    // nur Kopplung zwischen ViewModel und Fenster-Controller.
    refresh()
  }

  func moveSelection(_ delta: Int) {
    let count = visible.count
    guard count > 0 else { return }
    selectedIndex = min(count - 1, max(0, selectedIndex + delta))
  }

  // MARK: - Aktionen (mit Index-Guards statt count >= index!)

  func copySelected(paste: Bool) {
    let list = visible
    guard list.indices.contains(selectedIndex) else { return }
    let item = list[selectedIndex]

    writeToPasteboard(item)
    HistoryStore.shared.markUsed(id: item.id)

    let shouldPaste = paste || AppSettings.pasteByDefault
    if shouldPaste {
      if PasteSupport.isTrusted() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
          PasteSupport.paste()
        }
      } else {
        PasteSupport.promptIfNotTrusted() // Fix: nie wieder stummes Scheitern
      }
    }
    DispatchQueue.main.async { self.onDismiss?() }
    refresh()
  }

  func deleteSelected() {
    let list = visible
    guard list.indices.contains(selectedIndex) else { return }
    let item = list[selectedIndex]
    HistoryStore.shared.delete(id: item.id)
    refresh()
  }

  func togglePinSelected() {
    let list = visible
    guard list.indices.contains(selectedIndex) else { return }
    let item = list[selectedIndex]
    HistoryStore.shared.setPin(id: item.id, pinned: !item.pinned)
    refresh()
  }

  func clearUnpinned() {
    HistoryStore.shared.clearAll(keepPinned: true)
    refresh()
  }

  // MARK: - Pasteboard zurückschreiben

  private func writeToPasteboard(_ item: DisplayItem) {
    let pb = NSPasteboard.general
    pb.clearContents()
    let pasteItem = NSPasteboardItem()
    for content in item.contents {
      pasteItem.setData(content.value, forType: NSPasteboard.PasteboardType(content.type))
    }
    // Konventionskonform (nspasteboard.org): Original-Quelle mitliefern.
    if let source = item.sourceApp {
      pasteItem.setString(source, forType: .nspasteboardSource)
    }
    // Eigener Marker: verhindert, dass die Rückkopie aufgezeichnet wird.
    pasteItem.setString("", forType: .safepasteRestored)
    pb.writeObjects([pasteItem])
  }
}
