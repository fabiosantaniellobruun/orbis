import Foundation
import Security

/// Le password stanno nel Portachiavi di login, una per elemento; l'elemento ne conserva solo il
/// nome (`account`). L'app che le crea può rileggerle senza conferme, finché la firma non cambia.
nonisolated enum PasswordStore {
  private static let service = "it.fabiosbruun.OrbisClip"

  enum PasswordError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
      switch self {
      case .keychain(let status):
        "Il Portachiavi non ha salvato la password: \(SecCopyErrorMessageString(status, nil) as String? ?? "errore \(status)")."
      }
    }
  }

  private static func query(_ account: String) -> [CFString: Any] {
    [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
  }

  static func save(_ password: String, account: String) throws {
    let data = Data(password.utf8)
    var status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData: data] as CFDictionary)
    if status == errSecItemNotFound {
      var item = query(account)
      item[kSecValueData] = data
      item[kSecAttrLabel] = "Orbis Clip"
      status = SecItemAdd(item as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw PasswordError.keychain(status) }
  }

  static func password(account: String) -> String? {
    var item = query(account)
    item[kSecReturnData] = true
    item[kSecMatchLimit] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func delete(account: String) {
    SecItemDelete(query(account) as CFDictionary)
  }
}
