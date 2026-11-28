import CryptoKit
import DeviceCheck
import Foundation
import Security

/// Who this install is to our backend, without an account: a random install id
/// in the keychain, Apple's DeviceCheck token (two bits per device that survive
/// reinstalling) and, where supported, an App Attest key.
@MainActor
enum AssistantDeviceIdentity {
    private static let service = "ayurvedaasanayoga.assistant"

    static var installID: String {
        if let existing = Keychain.read(service: service, account: "installID") { return existing }
        let fresh = UUID().uuidString
        Keychain.write(fresh, service: service, account: "installID")
        return fresh
    }

    static var attestKeyID: String? {
        get { Keychain.read(service: service, account: "attestKeyID") }
        set {
            if let newValue { Keychain.write(newValue, service: service, account: "attestKeyID") }
            else { Keychain.delete(service: service, account: "attestKeyID") }
        }
    }

    static var deviceToken: String? {
        get { Keychain.read(service: service, account: "deviceToken") }
        set {
            if let newValue { Keychain.write(newValue, service: service, account: "deviceToken") }
            else { Keychain.delete(service: service, account: "deviceToken") }
        }
    }

    /// A fresh DeviceCheck token, or nil on the simulator and unsupported devices.
    static func deviceCheckToken() async -> String? {
        guard DCDevice.current.isSupported else { return nil }
        return try? await DCDevice.current.generateToken().base64EncodedString()
    }

    /// Makes (once) and attests an App Attest key over the server's challenge.
    /// Returns nil where App Attest is unavailable (simulator, no entitlement).
    static func attest(challenge: String) async -> (keyID: String, attestation: String)? {
        let service = DCAppAttestService.shared
        guard service.isSupported else { return nil }
        do {
            let keyID = try await service.generateKey()
            let hash = Data(SHA256.hash(data: Data(base64Encoded: challenge) ?? Data()))
            let attestation = try await service.attestKey(keyID, clientDataHash: hash)
            attestKeyID = keyID
            return (keyID, attestation.base64EncodedString())
        } catch {
            return nil
        }
    }

    /// An assertion over the server's challenge with the attested key.
    static func assertion(challenge: String) async -> String? {
        guard DCAppAttestService.shared.isSupported, let keyID = attestKeyID else { return nil }
        let hash = Data(SHA256.hash(data: Data(base64Encoded: challenge) ?? Data()))
        return try? await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: hash).base64EncodedString()
    }
}

/// Small keychain wrapper: device-only items, not synced to other devices.
enum Keychain {
    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, service: String, account: String) {
        delete(service: service, account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
