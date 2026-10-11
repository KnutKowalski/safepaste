import Foundation
import SQLite3
import CryptoKit

/// Speicher: SQLite (System-Bibliothek, keine Abhängigkeit).
///
/// Sicherheits- und Robustheits-Designentscheidungen:
/// - `secure_delete=ON` + `VACUUM` nach "Alles löschen" → Löschung ist belastbar.
/// - Inhalt NUR verschlüsselt (BLOB) – niemals Klartext in der DB.
/// - Kein fatalError: Fällt die DB aus, läuft die App weiter und loggt (Maccy: Absturz-Loop).
/// - Alle Fehler werden geloggt, niemals still geschluckt.
final class HistoryStore {
  static let shared = HistoryStore()

  private let queue = DispatchQueue(label: "org.safepaste.store", qos: .utility)
  private var db: OpaquePointer?
  private let SQLITE_TRANSIENT = unsafeBitCast(
    OpaquePointer(bitPattern: -1),
    to: sqlite3_destructor_type.self
  )

  private struct Payload: Codable {
    let preview: String
    let fullText: String
    let contents: [StoredContent]
  }

  private struct Row {
    let id: String
    let lastUsed: Double
    let copies: Int
    let pinned: Bool
    let sourceApp: String?
    let kind: String
    let hash: String
    let payload: Data
  }

  private init() {
    queue.sync { openIfNeeded() }
  }

  // MARK: - Öffnen & Schema

  private func openIfNeeded() {
    guard db == nil else { return }

    let fm = FileManager.default
    let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("SafePaste", isDirectory: true)
    do {
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    } catch {
      Log.error("Support-Ordner nicht anlegbar: \(error.localizedDescription)")
      return
    }
    let url = dir.appendingPathComponent("history.sqlite")

    var handle: OpaquePointer?
    let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
    guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
      Log.error("Datenbank nicht öffnbar (korrupt?) – Historie bleibt temporär deaktiviert, kein Absturz.")
      if handle != nil { sqlite3_close(handle) }
      return
    }
    db = handle

    exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA secure_delete=ON;")
    exec("""
      CREATE TABLE IF NOT EXISTS items(
        id TEXT PRIMARY KEY,
        created REAL NOT NULL,
        last_used REAL NOT NULL,
        copies INTEGER NOT NULL DEFAULT 1,
        pin INTEGER NOT NULL DEFAULT 0,
        source_app TEXT,
        kind TEXT NOT NULL,
        content_hash TEXT NOT NULL UNIQUE,
        payload BLOB NOT NULL
      );
      """)
    exec("CREATE INDEX IF NOT EXISTS items_last_used ON items(last_used DESC);")
  }

  @discardableResult
  private func exec(_ sql: String) -> Bool {
    guard let db else { return false }
    var message: UnsafeMutablePointer<CChar>?
    let rc = sqlite3_exec(db, sql, nil, nil, &message)
    if rc != SQLITE_OK {
      let text = message.map { String(cString: $0) } ?? "unbekannt"
      Log.error("SQLite-Fehler: \(text)")
      if let message { sqlite3_free(message) }
      return false
    }
    return true
  }

  // MARK: - Hinzufügen (Hash-Dedup statt Voll-Blob-Vergleich)

  func add(_ record: ClipboardRecord) {
    queue.async {
      guard self.db != nil else {
        Log.error("Speichern übersprungen: keine Datenbank verfügbar.")
        return
      }

      var hasher = SHA256()
      for content in record.contents {
        hasher.update(data: content.value)
        hasher.update(data: Data(content.type.utf8))
      }
      let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()

      let payload = Payload(preview: record.preview, fullText: record.fullText, contents: record.contents)
      let plain: Data
      do {
        plain = try PropertyListEncoder().encode(payload)
      } catch {
        Log.error("Encoding fehlgeschlagen: \(error.localizedDescription)")
        return
      }
      let sealed: Data
      do {
        sealed = try Vault.encrypt(plain)
      } catch {
        Log.error("Verschlüsselung fehlgeschlagen – Eintrag wird NICHT gespeichert (fail closed).")
        return
      }

      if self.updateExisting(hash: hash, at: record.copiedAt) {
        return // Duplikat: nur Zeitstempel/Zähler aktualisiert.
      }
      if self.insertRow(id: record.id.uuidString, kind: record.kind.rawValue,
                        hash: hash, payload: sealed,
                        source: record.sourceApp, at: record.copiedAt) {
        self.enforceLimit()
      }
    }
  }

  private func updateExisting(hash: String, at date: Date) -> Bool {
    guard let db else { return false }
    var stmt: OpaquePointer?
    let sql = "UPDATE items SET last_used = ?1, copies = copies + 1 WHERE content_hash = ?2;"
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
      Log.error("UPDATE konnte nicht vorbereitet werden.")
      return false
    }
    defer { sqlite3_finalize(stmt) }
    sqlite3_bind_double(stmt, 1, date.timeIntervalSince1970)
    sqlite3_bind_text(stmt, 2, hash, -1, SQLITE_TRANSIENT)
    guard sqlite3_step(stmt) == SQLITE_DONE else { return false }
    return sqlite3_changes(db) > 0
  }

  private func insertRow(id: String, kind: String, hash: String, payload: Data,
                         source: String?, at date: Date) -> Bool {
    guard let db else { return false }
    var stmt: OpaquePointer?
    let sql = """
      INSERT INTO items(id, created, last_used, copies, pin, source_app, kind, content_hash, payload)
      VALUES(?1, ?2, ?2, 1, 0, ?3, ?4, ?5, ?6);
      """
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
      Log.error("INSERT konnte nicht vorbereitet werden.")
      return false
    }
    defer { sqlite3_finalize(stmt) }
    sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
    sqlite3_bind_double(stmt, 2, date.timeIntervalSince1970)
    if let source {
      sqlite3_bind_text(stmt, 3, source, -1, SQLITE_TRANSIENT)
    } else {
      sqlite3_bind_null(stmt, 3)
    }
    sqlite3_bind_text(stmt, 4, kind, -1, SQLITE_TRANSIENT)
    sqlite3_bind_text(stmt, 5, hash, -1, SQLITE_TRANSIENT)
    payload.withUnsafeBytes { buffer in
      _ = sqlite3_bind_blob(stmt, 6, buffer.baseAddress,
                            Int32(payload.count), SQLITE_TRANSIENT)
    }
    guard sqlite3_step(stmt) == SQLITE_DONE else {
      Log.error("INSERT fehlgeschlagen (evtl. Hash-Kollision).")
      return false
    }
    return true
  }

  /// Sichere Größenbegrenzung: funktioniert für JEDE Größe ohne Index-Crash.
  private func enforceLimit() {
    let limit = AppSettings.historySize
    exec("""
      DELETE FROM items
      WHERE pin = 0
        AND id NOT IN (SELECT id FROM items WHERE pin = 0 ORDER BY last_used DESC LIMIT \(limit));
      """)
  }

  // MARK: - Lesen (Entschlüsselung außerhalb des Main-Threads)

  func loadAll() -> [DisplayItem] {
    queue.sync {
      guard let db else { return [] }
      var rows: [Row] = []
      var stmt: OpaquePointer?
      let sql = """
        SELECT id, last_used, copies, pin, source_app, kind, content_hash, payload
        FROM items ORDER BY pin DESC, last_used DESC;
        """
      guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
        Log.error("SELECT konnte nicht vorbereitet werden.")
        return []
      }
      defer { sqlite3_finalize(s) }
      while sqlite3_step(s) == SQLITE_ROW {
        func text(_ index: Int32) -> String {
          guard let cString = sqlite3_column_text(s, index) else { return "" }
          return String(cString: cString)
        }
        func optionalText(_ index: Int32) -> String? {
          guard let cString = sqlite3_column_text(s, index) else { return nil }
          return String(cString: cString)
        }
        let blob: Data
        if let bytes = sqlite3_column_blob(s, 7) {
          let count = Int(sqlite3_column_bytes(s, 7))
          blob = Data(bytes: bytes, count: count)
        } else {
          continue
        }
        rows.append(Row(
          id: text(0),
          lastUsed: sqlite3_column_double(s, 1),
          copies: Int(sqlite3_column_int(s, 2)),
          pinned: sqlite3_column_int(s, 3) != 0,
          sourceApp: optionalText(4),
          kind: text(5),
          hash: text(6),
          payload: blob
        ))
      }

      var items: [DisplayItem] = []
      for row in rows {
        do {
          let plain = try Vault.decrypt(row.payload)
          let payload = try PropertyListDecoder().decode(Payload.self, from: plain)
          items.append(DisplayItem(
            id: row.id,
            kind: ItemKind(rawValue: row.kind) ?? .text,
            preview: payload.preview,
            fullText: payload.fullText,
            sourceApp: row.sourceApp,
            pinned: row.pinned,
            lastUsed: Date(timeIntervalSince1970: row.lastUsed),
            copies: row.copies,
            contents: payload.contents
          ))
        } catch {
          // Eintrag überspringen, aber sichtbar loggen – niemals still.
          Log.error("Eintrag konnte nicht entschlüsselt werden und wird übersprungen.")
        }
      }
      return items
    }
  }

  // MARK: - Mutationen

  func markUsed(id: String) {
    queue.async {
      self.exec("UPDATE items SET last_used = strftime('%s','now') WHERE id = '\(id)';")
    }
  }

  func setPin(id: String, pinned: Bool) {
    queue.async {
      self.exec("UPDATE items SET pin = \(pinned ? 1 : 0) WHERE id = '\(id)';")
    }
  }

  func delete(id: String) {
    queue.async {
      self.exec("DELETE FROM items WHERE id = '\(id)';")
    }
  }

  func clearAll(keepPinned: Bool) {
    queue.async {
      guard self.db != nil else { return }
      if keepPinned {
        self.exec("DELETE FROM items WHERE pin = 0;")
      } else {
        self.exec("DELETE FROM items;")
      }
      // Belastbares Löschen: secure_delete=ON überschreibt, VACUUM räumt Seiten ab.
      self.exec("VACUUM;")
    }
  }
}
