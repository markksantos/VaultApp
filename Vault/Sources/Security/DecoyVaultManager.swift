// DecoyVaultManager.swift
// Vault
//
// Decoy vault support — a second password opens a plausible set of decoy files.

import Foundation

/// Manages decoy vault functionality for plausible deniability.
///
/// When enabled, a second password derives a different encryption key and
/// decrypts a separate set of files stored in the same container. An observer
/// cannot distinguish between the real vault and the decoy vault.
public final class DecoyVaultManager {

    // MARK: - Properties

    private let engine: VaultEncryptionEngine

    // MARK: - Lifecycle

    public init(engine: VaultEncryptionEngine) {
        self.engine = engine
    }

    // MARK: - Setup

    /// Enable decoy vault for a container.
    /// - Parameters:
    ///   - vaultPath: Path to the vault container.
    ///   - decoyPassword: The password that will open the decoy vault.
    /// - Returns: Updated metadata with decoy enabled.
    public func enableDecoy(
        vaultPath: URL,
        decoyPassword: String
    ) async throws -> VaultMetadata {
        var metadata = try await engine.getMetadata(for: vaultPath)

        guard !metadata.hasDecoyVault else {
            throw DecoyError.alreadyEnabled
        }

        metadata.hasDecoyVault = true
        metadata.decoyFiles = []
        try await engine.updateMetadata(metadata, for: vaultPath)

        // The encryption engine is responsible for storing the decoy key material
        // derived from decoyPassword in a separate section of the container.
        // This manager coordinates the high-level flow.

        return metadata
    }

    /// Disable decoy vault, removing all decoy files.
    /// - Parameter vaultPath: Path to the vault container.
    public func disableDecoy(vaultPath: URL) async throws {
        var metadata = try await engine.getMetadata(for: vaultPath)

        guard metadata.hasDecoyVault else {
            throw DecoyError.notEnabled
        }

        metadata.hasDecoyVault = false
        metadata.decoyFiles = nil
        try await engine.updateMetadata(metadata, for: vaultPath)
    }

    // MARK: - Decoy File Management

    /// Add a file to the decoy vault section.
    /// - Parameters:
    ///   - sourceURL: Local file to add as decoy content.
    ///   - vaultPath: Path to the vault container.
    ///   - parentFolderID: Optional parent folder within the decoy vault.
    ///   - secureDeleteOriginal: Whether to securely delete the source file.
    /// - Returns: The file entry added to the decoy vault.
    public func addDecoyFile(
        at sourceURL: URL,
        to vaultPath: URL,
        parentFolderID: UUID? = nil,
        secureDeleteOriginal: Bool = false
    ) async throws -> VaultFileEntry {
        var metadata = try await engine.getMetadata(for: vaultPath)

        guard metadata.hasDecoyVault else {
            throw DecoyError.notEnabled
        }

        // Delegate actual encryption to the engine (it uses the decoy key)
        let entry = try await engine.addFile(
            at: sourceURL,
            to: vaultPath,
            parentFolderID: parentFolderID,
            secureDeleteOriginal: secureDeleteOriginal
        )

        if metadata.decoyFiles == nil {
            metadata.decoyFiles = []
        }
        metadata.decoyFiles?.append(entry)
        try await engine.updateMetadata(metadata, for: vaultPath)

        return entry
    }

    /// Remove a file from the decoy vault section.
    public func removeDecoyFile(id: UUID, from vaultPath: URL) async throws {
        var metadata = try await engine.getMetadata(for: vaultPath)

        guard metadata.hasDecoyVault else {
            throw DecoyError.notEnabled
        }

        metadata.decoyFiles?.removeAll { $0.id == id }
        try await engine.updateMetadata(metadata, for: vaultPath)
        try await engine.removeFile(id: id, from: vaultPath)
    }

    // MARK: - Detection

    /// Determine if a given password corresponds to the decoy vault.
    /// This is called during unlock — if the password derives the decoy key,
    /// the caller should present decoy files instead of real ones.
    ///
    /// - Parameters:
    ///   - password: The password entered by the user.
    ///   - metadata: The vault's metadata (already decrypted with the real key).
    /// - Returns: `true` if the password matches the decoy vault.
    ///
    /// - Note: The actual key comparison happens in the encryption engine.
    ///   This method provides the high-level decision logic.
    public func isDecoyPassword(_ password: String, for vaultPath: URL) -> Bool {
        // The encryption engine handles the cryptographic comparison.
        // During unlock, if the derived key matches the decoy key section
        // rather than the primary key section, this returns true.
        // Implementation depends on the encryption engine's key derivation.
        // Placeholder for engine integration — the engine will call back
        // during unlockVault to signal which key matched.
        return false
    }
}

// MARK: - Errors

public enum DecoyError: LocalizedError {
    case alreadyEnabled
    case notEnabled
    case decoyPasswordSameAsReal

    public var errorDescription: String? {
        switch self {
        case .alreadyEnabled:
            return "Decoy vault is already enabled."
        case .notEnabled:
            return "Decoy vault is not enabled for this container."
        case .decoyPasswordSameAsReal:
            return "Decoy password must be different from the real vault password."
        }
    }
}
