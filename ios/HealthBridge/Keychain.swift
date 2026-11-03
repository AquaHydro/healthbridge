import Foundation
import Security

enum Keychain {
  private static let service = "app.yiliang.healthbridge.ingest"
  private static var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: "ingest",
    ]
  }
  static func read() throws -> String {
    var q = query
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var value: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess,
      let data = value as? Data, let token = String(data: data, encoding: .utf8)
    else { throw BridgeError.keychain }
    return token
  }
  static func save(_ token: String) throws {
    let attrs: [String: Any] = [
      kSecValueData as String: Data(token.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
    if status == errSecItemNotFound {
      var q = query
      q.merge(attrs) { _, new in new }
      guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw BridgeError.keychain }
    } else if status != errSecSuccess {
      throw BridgeError.keychain
    }
  }
  static func delete() { SecItemDelete(query as CFDictionary) }
}
