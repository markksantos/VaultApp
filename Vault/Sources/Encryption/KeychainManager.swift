// KeychainManager.swift
// Vault
//
// Keychain storage for vault encryption keys with Touch ID access control.

import Foundation
import Security
import LocalAuthentication

public enum KeychainManager {

    private static let servicePrefix = "com.vault.encryption"

    // MARK: - Store

    /// Store a vault's encryption key in the Keychain, optionally requiring Touch ID to retrieve.
    ///
    /// - Parameters:
    ///   - key: Raw key bytes to store.
    ///   - vaultID: Unique vault identifier.
    ///   - withTouchID: If true, access requires biometric authentication.
    /// - Throws: `VaultError.encryptionFailed` on failure.
    public static func storeKey(_ key: Data, for vaultID: UUID, withTouchID: Bool) throws {
        // Delete any existing entry first to avoid errSecDuplicateItem.
        try? deleteKey(for: vaultID)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicePrefix,
            kSecAttrAccount as String: vaultID.uuidString,
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        if withTouchID {
            var error: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .biometryCurrentSet,
                &error
            ) else {
                throw VaultError.touchIDNotAvailable
            }

            // Replace the plain accessible attribute with the access control object.
            query.removeValue(forKey: kSecAttrAccessible as String)
            query[kSecAttrAccessControl as String] = access
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw VaultError.encryptionFailed("Keychain store failed: \(status)")
        }
    }

    // MARK: - Retrieve

    /// Retrieve a vault's encryption key from the Keychain. If the key was stored
    /// with Touch ID protection, this call triggers the biometric prompt.
    ///
    /// - Parameter vaultID: Unique vault identifier.
    /// - Returns: Raw key bytes.
    /// - Throws: `VaultError.touchIDAuthFailed` if biometric auth fails,
    ///           `VaultError.fileNotFound` if no key is stored.
    public static func retrieveKey(for vaultID: UUID) throws -> Data {
        let context = LAContext()
        context.localizedReason = "Unlock vault"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicePrefix,
            kSecAttrAccount as String: vaultID.uuidString,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw VaultError.decryptionFailed("Keychain returned invalid data")
            }
            return data
        case errSecItemNotFound:
            throw VaultError.fileNotFound("Keychain entry for vault \(vaultID.uuidString)")
        case errSecAuthFailed, errSecUserCanceled:
            throw VaultError.touchIDAuthFailed
        default:
            throw VaultError.decryptionFailed("Keychain retrieve failed: \(status)")
        }
    }

    // MARK: - Delete

    /// Delete the stored key for a vault from the Keychain.
    public static func deleteKey(for vaultID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicePrefix,
            kSecAttrAccount as String: vaultID.uuidString,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultError.secureDeleteFailed("Keychain delete failed: \(status)")
        }
    }

    // MARK: - Availability

    /// Check whether biometric authentication is available on this device.
    public static var isTouchIDAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
}
