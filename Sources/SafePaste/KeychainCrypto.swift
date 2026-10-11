import Foundation
import Security
import CryptoKit

enum VaultError: Error {
  case keychainFailure(OSStatus)
  case encryptionFailure
}

enum Keychain {
  private static let service = "org.safepaste.SafePaste.masterkey"
  private static let account = "master"

  /// Leggt den symmetrischen Schlüssel einmalig an und liest ihn danach aus dem Keychain.
  /// ThisDeviceOnly: kein Backup-/Sync-Export des Schlüssels.
  static func loadOrCreateKey() throws -> SymmetricKey {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecSuccess, let data = item as? Data {
      return SymmetricKey(data: data)
    }
    guard status == errSecItemNotFound else {
      throw VaultError.keychainFailure(status)
    }

    let key = SymmetricKey(size: .bits256)
    let keyData = key.withUnsafeBytes { Data($0) }
    let add: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: keyData,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]
    let addStatus = SecItemAdd(add as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw VaultError.keychainFailure(addStatus)
    }
    return key
  }
}

/// Transparente Verschlüsselung: ALLE Inhalte (inkl. Vorschau) werden
/// AES-256-GCM-verschlüsselt, bevor sie die Datenbank berühren.
/// Fail closed: Wenn nicht verschlüsselt werden kann, wird nichts gespeichert.
enum Vault {
  private static var cachedKey: SymmetricKey?
  private static let lock = NSLock()

  private static func currentKey() throws -> SymmetricKey {
    lock.lock()
    defer { lock.unlock() }
    if let cachedKey {
      return cachedKey
    }
    let key = try Keychain.loadOrCreateKey()
    cachedKey = key
    return key
  }

  static func encrypt(_ plaintext: Data) throws -> Data {
    let key = try currentKey()
    let sealed = try AES.GCM.seal(plaintext, using: key)
    guard let combined = sealed.combined else {
      throw VaultError.encryptionFailure
    }
    return combined
  }

  static func decrypt(_ combined: Data) throws -> Data {
    let key = try currentKey()
    let box = try AES.GCM.SealedBox(combined: combined)
    return try AES.GCM.open(box, using: key)
  }
}
