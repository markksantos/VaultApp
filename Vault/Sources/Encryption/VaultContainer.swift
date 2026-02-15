// VaultContainer.swift
// Vault
//
// Binary container format for vault files.
// Layout: [Header (67 bytes)] [Encrypted Metadata] [File Data Blocks...]

import Foundation
import CryptoKit

public enum VaultContainer {

    // MARK: - Header I/O

    /// Write a new container file with the given header and encrypted metadata.
    public static func createContainer(
        at url: URL,
        header: VaultContainerHeader,
        encryptedMetadata: Data
    ) throws {
        let headerData = serializeHeader(header)
        var containerData = Data()
        containerData.append(headerData)
        containerData.append(encryptedMetadata)

        do {
            try containerData.write(to: url, options: .atomic)
        } catch {
            throw VaultError.containerWriteFailed(error.localizedDescription)
        }
    }

    /// Read the fixed-size header from a container file.
    public static func readHeader(at url: URL) throws -> VaultContainerHeader {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VaultError.containerNotFound
        }

        guard let handle = FileHandle(forReadingAtPath: url.path) else {
            throw VaultError.containerNotFound
        }
        defer { handle.closeFile() }

        guard let headerData = try? handle.read(upToCount: VaultContainerHeader.fixedSize),
              headerData.count == VaultContainerHeader.fixedSize else {
            throw VaultError.invalidContainer
        }

        return try deserializeHeader(headerData)
    }

    // MARK: - Metadata I/O

    /// Read and decrypt the metadata block from the container.
    public static func readMetadata(at url: URL, key: SymmetricKey) throws -> VaultMetadata {
        let header = try readHeader(at: url)

        guard let handle = FileHandle(forReadingAtPath: url.path) else {
            throw VaultError.containerNotFound
        }
        defer { handle.closeFile() }

        handle.seek(toFileOffset: UInt64(VaultContainerHeader.fixedSize))
        guard let encryptedMetadata = try? handle.read(upToCount: Int(header.metadataLength)),
              encryptedMetadata.count == Int(header.metadataLength) else {
            throw VaultError.corruptedMetadata
        }

        let jsonData = try AESEncryptor.decrypt(
            ciphertext: encryptedMetadata,
            nonce: header.metadataNonce,
            key: key
        )

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(VaultMetadata.self, from: jsonData)
        } catch {
            throw VaultError.corruptedMetadata
        }
    }

    /// Encrypt and write updated metadata to the container. Rewrites the header with
    /// the new metadata length and nonce, then rewrites the metadata block.
    /// File data blocks are preserved by reading them first and rewriting after.
    public static func writeMetadata(
        _ metadata: VaultMetadata,
        to url: URL,
        key: SymmetricKey,
        header: VaultContainerHeader
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(metadata)

        let (encryptedMetadata, metadataNonce) = try AESEncryptor.encrypt(data: jsonData, key: key)

        // Read existing file data blocks (everything after old metadata).
        let fileData = try readFileDataSection(at: url, header: header)

        // Build updated header.
        let updatedHeader = VaultContainerHeader(
            magic: header.magic,
            version: header.version,
            salt: header.salt,
            metadataNonce: metadataNonce,
            metadataLength: UInt64(encryptedMetadata.count),
            kdfAlgorithm: header.kdfAlgorithm,
            kdfIterations: header.kdfIterations,
            kdfMemory: header.kdfMemory
        )

        // Rewrite the entire container atomically.
        var containerData = Data()
        containerData.append(serializeHeader(updatedHeader))
        containerData.append(encryptedMetadata)
        containerData.append(fileData)

        do {
            try containerData.write(to: url, options: .atomic)
        } catch {
            throw VaultError.containerWriteFailed(error.localizedDescription)
        }
    }

    // MARK: - File Block I/O

    /// Append an encrypted file block to the end of the container and return its
    /// offset relative to the start of the file data section.
    public static func appendFileBlock(
        encryptedData: Data,
        to url: URL,
        header: VaultContainerHeader
    ) throws -> UInt64 {
        guard let handle = FileHandle(forWritingAtPath: url.path) else {
            throw VaultError.containerWriteFailed("Cannot open container for writing")
        }
        defer { handle.closeFile() }

        // File data section starts after header + metadata.
        let dataSectionStart = UInt64(VaultContainerHeader.fixedSize) + header.metadataLength

        // Seek to end to get offset relative to data section.
        handle.seekToEndOfFile()
        let currentEnd = handle.offsetInFile
        let relativeOffset = currentEnd - dataSectionStart

        handle.write(encryptedData)
        return relativeOffset
    }

    /// Read an encrypted file block from the container.
    public static func readFileBlock(
        at url: URL,
        header: VaultContainerHeader,
        offset: UInt64,
        size: UInt64
    ) throws -> Data {
        guard let handle = FileHandle(forReadingAtPath: url.path) else {
            throw VaultError.containerNotFound
        }
        defer { handle.closeFile() }

        let dataSectionStart = UInt64(VaultContainerHeader.fixedSize) + header.metadataLength
        handle.seek(toFileOffset: dataSectionStart + offset)

        guard let data = try? handle.read(upToCount: Int(size)),
              data.count == Int(size) else {
            throw VaultError.decryptionFailed("Incomplete file block read")
        }
        return data
    }

    /// Read the entire file data section (everything after the metadata block).
    private static func readFileDataSection(
        at url: URL,
        header: VaultContainerHeader
    ) throws -> Data {
        guard let handle = FileHandle(forReadingAtPath: url.path) else {
            throw VaultError.containerNotFound
        }
        defer { handle.closeFile() }

        let dataSectionStart = UInt64(VaultContainerHeader.fixedSize) + header.metadataLength
        handle.seek(toFileOffset: dataSectionStart)

        return handle.readDataToEndOfFile()
    }

    // MARK: - Compaction

    /// Compact the container by rewriting only live (non-removed) file blocks.
    /// Returns the updated file entries with corrected offsets.
    public static func compact(
        at url: URL,
        metadata: VaultMetadata,
        key: SymmetricKey,
        header: VaultContainerHeader
    ) throws -> [VaultFileEntry] {
        // Read all live file blocks into memory in order.
        var liveBlocks: [(entry: VaultFileEntry, data: Data)] = []

        for entry in metadata.files where !entry.isFolder {
            let block = try readFileBlock(
                at: url,
                header: header,
                offset: entry.offset,
                size: entry.size
            )
            liveBlocks.append((entry: entry, data: block))
        }

        // Rebuild the file data section with contiguous blocks.
        var updatedEntries = metadata.files
        var newFileData = Data()

        for (entry, data) in liveBlocks {
            let newOffset = UInt64(newFileData.count)
            if let index = updatedEntries.firstIndex(where: { $0.id == entry.id }) {
                updatedEntries[index] = VaultFileEntry(
                    id: entry.id,
                    name: entry.name,
                    originalExtension: entry.originalExtension,
                    size: entry.size,
                    offset: newOffset,
                    nonce: entry.nonce,
                    parentFolderID: entry.parentFolderID,
                    createdDate: entry.createdDate,
                    modifiedDate: entry.modifiedDate,
                    isFolder: entry.isFolder,
                    mimeType: entry.mimeType,
                    thumbnailData: entry.thumbnailData
                )
            }
            newFileData.append(data)
        }

        // Preserve folder entries (they have no data blocks).
        // They're already in updatedEntries, no offset change needed.

        // Rewrite the container with compacted data.
        let updatedMetadata = VaultMetadata(
            vaultName: metadata.vaultName,
            createdDate: metadata.createdDate,
            lastModifiedDate: Date(),
            files: updatedEntries,
            touchIDEnabled: metadata.touchIDEnabled,
            autoLockInterval: metadata.autoLockInterval,
            hasDecoyVault: metadata.hasDecoyVault,
            decoyFiles: metadata.decoyFiles,
            failedAttemptCount: metadata.failedAttemptCount,
            lastFailedAttemptDate: metadata.lastFailedAttemptDate,
            wipeAfterMaxAttempts: metadata.wipeAfterMaxAttempts,
            maxFailedAttempts: metadata.maxFailedAttempts
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(updatedMetadata)
        let (encryptedMetadata, metadataNonce) = try AESEncryptor.encrypt(data: jsonData, key: key)

        let newHeader = VaultContainerHeader(
            magic: header.magic,
            version: header.version,
            salt: header.salt,
            metadataNonce: metadataNonce,
            metadataLength: UInt64(encryptedMetadata.count),
            kdfAlgorithm: header.kdfAlgorithm,
            kdfIterations: header.kdfIterations,
            kdfMemory: header.kdfMemory
        )

        var containerData = Data()
        containerData.append(serializeHeader(newHeader))
        containerData.append(encryptedMetadata)
        containerData.append(newFileData)

        do {
            try containerData.write(to: url, options: .atomic)
        } catch {
            throw VaultError.containerWriteFailed(error.localizedDescription)
        }

        return updatedEntries
    }

    // MARK: - Header Serialization

    public static func serializeHeader(_ header: VaultContainerHeader) -> Data {
        var data = Data()
        data.append(contentsOf: header.magic)                         // 4 bytes
        data.append(contentsOf: withUnsafeBytes(of: header.version.littleEndian) { Data($0) }) // 2 bytes
        data.append(header.salt)                                      // 32 bytes
        data.append(header.metadataNonce)                             // 12 bytes
        data.append(contentsOf: withUnsafeBytes(of: header.metadataLength.littleEndian) { Data($0) }) // 8 bytes
        data.append(header.kdfAlgorithm.rawValue)                     // 1 byte
        data.append(contentsOf: withUnsafeBytes(of: header.kdfIterations.littleEndian) { Data($0) }) // 4 bytes
        data.append(contentsOf: withUnsafeBytes(of: header.kdfMemory.littleEndian) { Data($0) })     // 4 bytes
        return data
    }

    public static func deserializeHeader(_ data: Data) throws -> VaultContainerHeader {
        guard data.count >= VaultContainerHeader.fixedSize else {
            throw VaultError.invalidContainer
        }

        var offset = 0

        // Magic bytes (4)
        let magic = [UInt8](data[offset..<offset+4])
        offset += 4
        guard magic == kVaultMagicBytes else {
            throw VaultError.invalidContainer
        }

        // Version (2)
        let version = data[offset..<offset+2].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }.littleEndian
        offset += 2

        // Salt (32)
        let salt = Data(data[offset..<offset+32])
        offset += 32

        // Metadata nonce (12)
        let metadataNonce = Data(data[offset..<offset+12])
        offset += 12

        // Metadata length (8)
        let metadataLength = data[offset..<offset+8].withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.littleEndian
        offset += 8

        // KDF algorithm (1)
        guard let kdfAlgorithm = KDFAlgorithm(rawValue: data[offset]) else {
            throw VaultError.invalidContainer
        }
        offset += 1

        // KDF iterations (4)
        let kdfIterations = data[offset..<offset+4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
        offset += 4

        // KDF memory (4)
        let kdfMemory = data[offset..<offset+4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian

        return VaultContainerHeader(
            magic: magic,
            version: version,
            salt: salt,
            metadataNonce: metadataNonce,
            metadataLength: metadataLength,
            kdfAlgorithm: kdfAlgorithm,
            kdfIterations: kdfIterations,
            kdfMemory: kdfMemory
        )
    }
}
