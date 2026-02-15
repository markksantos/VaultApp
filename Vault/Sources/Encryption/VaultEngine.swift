// VaultEngine.swift
// Vault
//
// Implements VaultEncryptionEngine protocol — the main public API for vault operations.
// Maintains an in-memory cache of unlocked vault keys. Keys are zeroed on lock.

import Foundation
import CryptoKit
import os

public final class VaultEngine: VaultEncryptionEngine {

    // MARK: - State

    /// In-memory cache: vault path string -> (SymmetricKey, current header, metadata).
    /// Keys are only present while a vault is unlocked.
    private struct UnlockedVault {
        let key: SymmetricKey
        var header: VaultContainerHeader
        var metadata: VaultMetadata
    }

    private let unlockedVaults = OSAllocatedUnfairLock(initialState: [String: UnlockedVault]())

    private let kdfParams = KeyDerivationParams.defaultPBKDF2

    public init() {}

    // MARK: - Create

    public func createVault(
        name: String,
        password: String,
        at path: URL,
        touchIDEnabled: Bool
    ) async throws -> VaultInfo {
        let salt = KeyDerivationService.generateSalt(length: kdfParams.saltLength)
        let key = try KeyDerivationService.deriveKey(password: password, salt: salt, params: kdfParams)

        let vaultID = UUID()
        let now = Date()

        let metadata = VaultMetadata(
            vaultName: name,
            createdDate: now,
            lastModifiedDate: now,
            files: [],
            touchIDEnabled: touchIDEnabled,
            autoLockInterval: .fiveMinutes,
            hasDecoyVault: false,
            decoyFiles: nil,
            failedAttemptCount: 0,
            lastFailedAttemptDate: nil,
            wipeAfterMaxAttempts: false,
            maxFailedAttempts: 10
        )

        // Encrypt metadata.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(metadata)
        let (encryptedMetadata, metadataNonce) = try AESEncryptor.encrypt(data: jsonData, key: key)

        let header = VaultContainerHeader(
            magic: kVaultMagicBytes,
            version: kVaultFormatVersion,
            salt: salt,
            metadataNonce: metadataNonce,
            metadataLength: UInt64(encryptedMetadata.count),
            kdfAlgorithm: kdfParams.algorithm,
            kdfIterations: kdfParams.iterations,
            kdfMemory: kdfParams.memory
        )

        try VaultContainer.createContainer(at: path, header: header, encryptedMetadata: encryptedMetadata)

        // Store key in Keychain for Touch ID if enabled.
        if touchIDEnabled {
            let keyData = key.withUnsafeBytes { Data($0) }
            try KeychainManager.storeKey(keyData, for: vaultID, withTouchID: true)
        }

        // Cache the unlocked vault.
        unlockedVaults.withLock { $0[path.path] = UnlockedVault(key: key, header: header, metadata: metadata) }

        return VaultInfo(
            id: vaultID,
            name: name,
            containerPath: path.path,
            createdDate: now,
            touchIDEnabled: touchIDEnabled,
            isDecoy: false
        )
    }

    // MARK: - Unlock

    public func unlockVault(at path: URL, password: String) async throws -> VaultMetadata {
        let header = try VaultContainer.readHeader(at: path)

        let params = KeyDerivationParams(
            algorithm: header.kdfAlgorithm,
            iterations: header.kdfIterations,
            memory: header.kdfMemory,
            saltLength: header.salt.count,
            keyLength: 32
        )

        let key = try KeyDerivationService.deriveKey(password: password, salt: header.salt, params: params)

        // Try decrypting metadata — if it fails, the password was wrong.
        let metadata: VaultMetadata
        do {
            metadata = try VaultContainer.readMetadata(at: path, key: key)
        } catch {
            throw VaultError.wrongPassword
        }

        unlockedVaults.withLock { $0[path.path] = UnlockedVault(key: key, header: header, metadata: metadata) }

        return metadata
    }

    public func unlockVaultWithTouchID(at path: URL) async throws -> VaultMetadata {
        // We need a vault ID to look up the Keychain entry. Parse the header to
        // get the container, then look up by a stable identifier.
        // Since the Keychain is keyed by vault UUID (stored externally), the caller
        // must have a VaultInfo. For now, we use the file path as a fallback identifier
        // hashed to a deterministic UUID.
        let header = try VaultContainer.readHeader(at: path)

        // Derive a deterministic UUID from the salt (unique per vault).
        let vaultID = deterministicUUID(from: header.salt)

        let keyData = try KeychainManager.retrieveKey(for: vaultID)
        let key = SymmetricKey(data: keyData)

        let metadata: VaultMetadata
        do {
            metadata = try VaultContainer.readMetadata(at: path, key: key)
        } catch {
            throw VaultError.touchIDAuthFailed
        }

        unlockedVaults.withLock { $0[path.path] = UnlockedVault(key: key, header: header, metadata: metadata) }

        return metadata
    }

    // MARK: - Lock

    public func lockVault(at path: URL) async throws {
        _ = unlockedVaults.withLock { $0.removeValue(forKey: path.path) }
    }

    // MARK: - File Operations

    public func addFile(
        at sourceURL: URL,
        to vaultPath: URL,
        parentFolderID: UUID?,
        secureDeleteOriginal: Bool
    ) async throws -> VaultFileEntry {
        var vault = try getUnlockedVault(for: vaultPath)

        let fileData = try Data(contentsOf: sourceURL)
        let fileName = sourceURL.lastPathComponent
        let fileExtension = sourceURL.pathExtension

        // Encrypt the file with its own unique nonce.
        let (encryptedData, nonce) = try AESEncryptor.encrypt(data: fileData, key: vault.key)

        // Append encrypted block to container.
        let offset = try VaultContainer.appendFileBlock(
            encryptedData: encryptedData,
            to: vaultPath,
            header: vault.header
        )

        let now = Date()
        let entry = VaultFileEntry(
            id: UUID(),
            name: fileName,
            originalExtension: fileExtension,
            size: UInt64(encryptedData.count),
            offset: offset,
            nonce: nonce,
            parentFolderID: parentFolderID,
            createdDate: now,
            modifiedDate: now,
            isFolder: false,
            mimeType: mimeType(for: fileExtension),
            thumbnailData: nil
        )

        // Update metadata.
        vault.metadata.files.append(entry)
        vault.metadata.lastModifiedDate = now
        try VaultContainer.writeMetadata(vault.metadata, to: vaultPath, key: vault.key, header: vault.header)

        // Refresh the cached header (metadata length/nonce may have changed).
        vault.header = try VaultContainer.readHeader(at: vaultPath)
        updateCache(vault, for: vaultPath)

        // Securely delete original if requested.
        if secureDeleteOriginal {
            try secureDelete(at: sourceURL)
        }

        return entry
    }

    public func removeFile(id: UUID, from vaultPath: URL) async throws {
        var vault = try getUnlockedVault(for: vaultPath)

        guard let removedFile = vault.metadata.files.first(where: { $0.id == id }) else {
            throw VaultError.fileNotFound(id.uuidString)
        }

        // Remove from metadata (data block remains until compaction).
        vault.metadata.files.removeAll { $0.id == id }
        vault.metadata.lastModifiedDate = Date()
        try VaultContainer.writeMetadata(vault.metadata, to: vaultPath, key: vault.key, header: vault.header)

        vault.header = try VaultContainer.readHeader(at: vaultPath)
        updateCache(vault, for: vaultPath)

        // Compact if fragmentation is significant
        compactIfNeeded(at: vaultPath, removedSize: removedFile.size)
    }

    public func readFile(id: UUID, from vaultPath: URL) async throws -> URL {
        let plaintext = try await readFileToMemory(id: id, from: vaultPath)
        let vault = try getUnlockedVault(for: vaultPath)

        guard let entry = vault.metadata.files.first(where: { $0.id == id }) else {
            throw VaultError.fileNotFound(id.uuidString)
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("vault_preview", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempURL = tempDir.appendingPathComponent(entry.name)

        try plaintext.write(to: tempURL)
        return tempURL
    }

    public func readFileToMemory(id: UUID, from vaultPath: URL) async throws -> Data {
        let vault = try getUnlockedVault(for: vaultPath)

        guard let entry = vault.metadata.files.first(where: { $0.id == id }) else {
            throw VaultError.fileNotFound(id.uuidString)
        }

        let encryptedBlock = try VaultContainer.readFileBlock(
            at: vaultPath,
            header: vault.header,
            offset: entry.offset,
            size: entry.size
        )

        return try AESEncryptor.decrypt(ciphertext: encryptedBlock, nonce: entry.nonce, key: vault.key)
    }

    public func exportFile(id: UUID, from vaultPath: URL, to destinationURL: URL) async throws {
        let plaintext = try await readFileToMemory(id: id, from: vaultPath)
        try plaintext.write(to: destinationURL)
    }

    public func createFolder(
        name: String,
        in vaultPath: URL,
        parentFolderID: UUID?
    ) async throws -> VaultFileEntry {
        var vault = try getUnlockedVault(for: vaultPath)

        let now = Date()
        let entry = VaultFileEntry(
            id: UUID(),
            name: name,
            originalExtension: "",
            size: 0,
            offset: 0,
            nonce: Data(),
            parentFolderID: parentFolderID,
            createdDate: now,
            modifiedDate: now,
            isFolder: true,
            mimeType: nil,
            thumbnailData: nil
        )

        vault.metadata.files.append(entry)
        vault.metadata.lastModifiedDate = now
        try VaultContainer.writeMetadata(vault.metadata, to: vaultPath, key: vault.key, header: vault.header)

        vault.header = try VaultContainer.readHeader(at: vaultPath)
        updateCache(vault, for: vaultPath)

        return entry
    }

    public func getMetadata(for vaultPath: URL) async throws -> VaultMetadata {
        let vault = try getUnlockedVault(for: vaultPath)
        return vault.metadata
    }

    public func updateMetadata(_ metadata: VaultMetadata, for vaultPath: URL) async throws {
        var vault = try getUnlockedVault(for: vaultPath)
        vault.metadata = metadata
        try VaultContainer.writeMetadata(vault.metadata, to: vaultPath, key: vault.key, header: vault.header)

        vault.header = try VaultContainer.readHeader(at: vaultPath)
        updateCache(vault, for: vaultPath)
    }

    // MARK: - Private Helpers

    private func getUnlockedVault(for path: URL) throws -> UnlockedVault {
        try unlockedVaults.withLock { state in
            guard let vault = state[path.path] else {
                throw VaultError.decryptionFailed("Vault is locked")
            }
            return vault
        }
    }

    private func updateCache(_ vault: UnlockedVault, for path: URL) {
        unlockedVaults.withLock { $0[path.path] = vault }
    }

    /// Compact the container if fragmentation exceeds 25% of total data size.
    private func compactIfNeeded(at vaultPath: URL, removedSize: UInt64) {
        guard removedSize > 0, let vault = try? getUnlockedVault(for: vaultPath) else { return }

        let liveDataSize = vault.metadata.files
            .filter { !$0.isFolder }
            .reduce(UInt64(0)) { $0 + $1.size }

        let totalDataSize = liveDataSize + removedSize
        let fragmentationRatio = Double(removedSize) / Double(totalDataSize)
        guard fragmentationRatio > 0.25 else { return }

        do {
            let updatedEntries = try VaultContainer.compact(
                at: vaultPath,
                metadata: vault.metadata,
                key: vault.key,
                header: vault.header
            )
            var updatedVault = vault
            updatedVault.metadata.files = updatedEntries
            updatedVault.header = try VaultContainer.readHeader(at: vaultPath)
            updateCache(updatedVault, for: vaultPath)
        } catch {
            // Compaction is best-effort; don't fail the removal
        }
    }

    /// Generate a deterministic UUID from data (used to map salt -> vault ID for Keychain lookups).
    private func deterministicUUID(from data: Data) -> UUID {
        let hash = SHA256.hash(data: data)
        var bytes = [UInt8](hash.prefix(16))
        // Set UUID version 5 bits.
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Simple MIME type lookup from file extension.
    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "doc", "docx": return "application/msword"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mp3": return "audio/mpeg"
        case "zip": return "application/zip"
        default: return "application/octet-stream"
        }
    }

    /// Overwrite a file's contents with random data before deleting.
    private func secureDelete(at url: URL) throws {
        guard let handle = FileHandle(forWritingAtPath: url.path) else {
            throw VaultError.secureDeleteFailed("Cannot open file for secure delete")
        }
        defer { handle.closeFile() }

        let fileSize = handle.seekToEndOfFile()
        handle.seek(toFileOffset: 0)

        // Overwrite with random bytes.
        var randomBytes = [UInt8](repeating: 0, count: Int(fileSize))
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        handle.write(Data(randomBytes))

        // Second pass: zeros.
        handle.seek(toFileOffset: 0)
        handle.write(Data(count: Int(fileSize)))

        handle.closeFile()

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw VaultError.secureDeleteFailed(error.localizedDescription)
        }
    }
}
