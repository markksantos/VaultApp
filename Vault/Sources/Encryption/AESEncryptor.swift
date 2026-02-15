// AESEncryptor.swift
// Vault
//
// AES-256-GCM encrypt/decrypt using CryptoKit.

import Foundation
import CryptoKit

public enum AESEncryptor {

    /// Encrypt plaintext data using AES-256-GCM.
    ///
    /// - Parameters:
    ///   - data: Plaintext data to encrypt.
    ///   - key: 256-bit symmetric key.
    /// - Returns: A tuple of (ciphertext including GCM tag, 12-byte nonce).
    /// - Throws: `VaultError.encryptionFailed` on failure.
    public static func encrypt(data: Data, key: SymmetricKey) throws -> (ciphertext: Data, nonce: Data) {
        do {
            let nonce = AES.GCM.Nonce()
            let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)

            // combined = nonce + ciphertext + tag; we store nonce separately, so use
            // ciphertext + tag only.
            guard let combined = sealedBox.combined else {
                throw VaultError.encryptionFailed("Failed to produce sealed box")
            }

            // combined layout: 12 bytes nonce | ciphertext | 16 bytes tag
            // Strip the leading 12-byte nonce since we store it separately.
            let ciphertextWithTag = combined.dropFirst(12)

            let nonceData = Data(nonce.withUnsafeBytes { Data($0) })

            return (ciphertext: Data(ciphertextWithTag), nonce: nonceData)
        } catch let error as VaultError {
            throw error
        } catch {
            throw VaultError.encryptionFailed(error.localizedDescription)
        }
    }

    /// Decrypt ciphertext data using AES-256-GCM.
    ///
    /// - Parameters:
    ///   - ciphertext: Ciphertext with appended GCM authentication tag (no nonce prefix).
    ///   - nonce: The 12-byte nonce used during encryption.
    ///   - key: 256-bit symmetric key.
    /// - Returns: Decrypted plaintext data.
    /// - Throws: `VaultError.decryptionFailed` on failure (wrong key, tampered data, etc.).
    public static func decrypt(ciphertext: Data, nonce: Data, key: SymmetricKey) throws -> Data {
        do {
            // Validate nonce format (will throw if invalid length)
            _ = try AES.GCM.Nonce(data: nonce)

            // Reconstruct the combined representation: nonce + ciphertext + tag
            var combined = Data(nonce)
            combined.append(ciphertext)

            let sealedBox = try AES.GCM.SealedBox(combined: combined)
            let plaintext = try AES.GCM.open(sealedBox, using: key)
            return plaintext
        } catch let error as VaultError {
            throw error
        } catch {
            throw VaultError.decryptionFailed(error.localizedDescription)
        }
    }

    /// Encrypt plaintext data with a specific nonce (used when re-encrypting with a known nonce).
    public static func encrypt(data: Data, key: SymmetricKey, nonce: AES.GCM.Nonce) throws -> Data {
        do {
            let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
            guard let combined = sealedBox.combined else {
                throw VaultError.encryptionFailed("Failed to produce sealed box")
            }
            // Strip leading 12-byte nonce
            return Data(combined.dropFirst(12))
        } catch let error as VaultError {
            throw error
        } catch {
            throw VaultError.encryptionFailed(error.localizedDescription)
        }
    }
}
