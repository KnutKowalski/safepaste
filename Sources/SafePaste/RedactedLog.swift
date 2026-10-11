import os

/// Protokollierung mit harter Regel: NIE Clipboard-Inhalte, nur Metadaten.
/// (Fix: Maccy loggt bis zu 1000 Zeichen kopierten Text ins Systemlog.)
enum Log {
  private static let logger = Logger(subsystem: "org.safepaste.SafePaste", category: "app")

  static func info(_ message: String) {
    logger.info("\(message, privacy: .public)")
  }

  static func error(_ message: String) {
    logger.error("\(message, privacy: .public)")
  }
}
