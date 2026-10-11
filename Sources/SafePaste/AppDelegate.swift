import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    PanelController.shared.setup()

    PasteboardMonitor.shared.onNewRecord = { record in
      HistoryStore.shared.add(record)
      DispatchQueue.main.async {
        PanelController.shared.viewModel.refreshIfVisible()
      }
    }
    PasteboardMonitor.shared.start()
  }

  func applicationWillTerminate(_ notification: Notification) {
    if AppSettings.clearOnQuit {
      HistoryStore.shared.clearAll(keepPinned: false)
    }
  }
}
