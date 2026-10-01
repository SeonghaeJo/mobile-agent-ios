import Foundation
import Security
import CryptoKit

public struct DeviceIdentity: Codable, Sendable { public let deviceId: String; public let publicKey: String; public let privateKey: String }

public final class SecureStore: @unchecked Sendable {
    public static let shared = SecureStore()
    private init() {}
    private func key(_ account: String) -> String { "openclaw.mobile.\(account)" }
    public func string(for account: String) -> String? { let q: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrAccount as String:key(account), kSecReturnData as String:true]; var result: CFTypeRef?; guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }; return String(data: data, encoding: .utf8) }
    public func set(_ value: String, for account: String) { let data = Data(value.utf8); let q: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrAccount as String:key(account), kSecValueData as String:data, kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]; SecItemDelete(q as CFDictionary); SecItemAdd(q as CFDictionary, nil) }
    public func identity() -> DeviceIdentity { if let raw = string(for: "device-identity"), let data = Data(base64Encoded: raw), let value = try? JSONDecoder().decode(DeviceIdentity.self, from: data) { return value }; let privateKey = Curve25519.Signing.PrivateKey(); let pub = privateKey.publicKey.rawRepresentation; let id = Data(SHA256.hash(data: pub)).map { String(format: "%02x", $0) }.joined(); let value = DeviceIdentity(deviceId: id, publicKey: pub.base64EncodedString(), privateKey: privateKey.rawRepresentation.base64EncodedString()); if let data = try? JSONEncoder().encode(value) { set(data.base64EncodedString(), for: "device-identity") }; return value }
    public func sign(_ payload: String, identity: DeviceIdentity) -> String? { guard let raw = Data(base64Encoded: identity.privateKey), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw), let sig = try? key.signature(for: Data(payload.utf8)) else { return nil }; return sig.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}
