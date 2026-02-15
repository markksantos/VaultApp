// KeyDerivation.swift
// Vault
//
// PBKDF2-HMAC-SHA256 key derivation with 600,000 iterations.
// Uses CommonCrypto's CCKeyDerivationPBKDF since CryptoKit doesn't expose PBKDF2 directly.
// Interface designed for future Argon2id swap via the KDFAlgorithm enum.

import Foundation
import CryptoKit
import CommonCrypto

// MARK: - Key Derivation Parameters

public struct KeyDerivationParams {
    public let algorithm: KDFAlgorithm
    public let iterations: UInt32
    public let memory: UInt32      // reserved for Argon2id
    public let saltLength: Int
    public let keyLength: Int

    public static let defaultPBKDF2 = KeyDerivationParams(
        algorithm: .pbkdf2HMACSHA256,
        iterations: 600_000,
        memory: 0,
        saltLength: 32,
        keyLength: 32  // 256-bit key
    )

    public init(algorithm: KDFAlgorithm, iterations: UInt32, memory: UInt32, saltLength: Int, keyLength: Int) {
        self.algorithm = algorithm
        self.iterations = iterations
        self.memory = memory
        self.saltLength = saltLength
        self.keyLength = keyLength
    }
}

// MARK: - Key Derivation Service

public enum KeyDerivationService {

    /// Generate a cryptographically random salt.
    public static func generateSalt(length: Int = 32) -> Data {
        var salt = Data(count: length)
        salt.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            // SecRandomCopyBytes is CSPRNG — suitable for salt generation
            _ = SecRandomCopyBytes(kSecRandomDefault, length, base)
        }
        return salt
    }

    /// Derive a symmetric key from a password and salt using the specified algorithm.
    ///
    /// - Parameters:
    ///   - password: The user's plaintext password.
    ///   - salt: Random salt (should be stored alongside the ciphertext).
    ///   - params: Key derivation parameters (algorithm, iterations, etc.).
    /// - Returns: A CryptoKit `SymmetricKey` suitable for AES-256-GCM.
    /// - Throws: `VaultError.keyDerivationFailed` on any failure.
    public static func deriveKey(
        password: String,
        salt: Data,
        params: KeyDerivationParams = .defaultPBKDF2
    ) throws -> SymmetricKey {
        switch params.algorithm {
        case .pbkdf2HMACSHA256:
            return try derivePBKDF2(password: password, salt: salt, params: params)
        case .argon2id:
            // Argon2id is not yet implemented — fail gracefully so callers know.
            throw VaultError.keyDerivationFailed
        }
    }

    // MARK: - PBKDF2

    private static func derivePBKDF2(
        password: String,
        salt: Data,
        params: KeyDerivationParams
    ) throws -> SymmetricKey {
        guard let passwordData = password.data(using: .utf8) else {
            throw VaultError.keyDerivationFailed
        }

        var derivedKeyBytes = [UInt8](repeating: 0, count: params.keyLength)

        let status = passwordData.withUnsafeBytes { passwordBuffer in
            salt.withUnsafeBytes { saltBuffer in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBuffer.baseAddress?.assumingMemoryBound(to: Int8.self),
                    passwordData.count,
                    saltBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    params.iterations,
                    &derivedKeyBytes,
                    params.keyLength
                )
            }
        }

        guard status == kCCSuccess else {
            throw VaultError.keyDerivationFailed
        }

        let key = SymmetricKey(data: derivedKeyBytes)

        // Zero the derived bytes buffer — the SymmetricKey has its own copy.
        memset_s(&derivedKeyBytes, derivedKeyBytes.count, 0, derivedKeyBytes.count)

        return key
    }
}
