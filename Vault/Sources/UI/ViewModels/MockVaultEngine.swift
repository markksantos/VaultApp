// MockVaultEngine.swift
// Vault
//
// Mock implementation of VaultEncryptionEngine for UI development and testing.

import Foundation

public final class MockVaultEngine: VaultEncryptionEngine {

    // MARK: - Mock State

    private var unlockedVaults: Set<URL> = []

    // Sample files to show in an unlocked vault
    public static let sampleFiles: [VaultFileEntry] = [
        VaultFileEntry(
            id: UUID(),
            name: "Tax Return 2024",
            originalExtension: "pdf",
            size: 2_450_000,
            offset: 0,
            nonce: Data(repeating: 0, count: 12),
            parentFolderID: nil,
            createdDate: Date().addingTimeInterval(-86400 * 30),
            modifiedDate: Date().addingTimeInterval(-86400 * 5),
            isFolder: false,
            mimeType: "application/pdf",
            thumbnailData: nil
        ),
        VaultFileEntry(
            id: UUID(),
            name: "Passport Scan",
            originalExtension: "jpg",
            size: 4_100_000,
            offset: 0,
            nonce: Data(repeating: 0, count: 12),
            parentFolderID: nil,
            createdDate: Date().addingTimeInterval(-86400 * 90),
            modifiedDate: Date().addingTimeInterval(-86400 * 90),
            isFolder: false,
            mimeType: "image/jpeg",
            thumbnailData: nil
        ),
        VaultFileEntry(
            id: UUID(),
            name: "Passwords",
            originalExtension: "txt",
            size: 1_200,
            offset: 0,
            nonce: Data(repeating: 0, count: 12),
            parentFolderID: nil,
            createdDate: Date().addingTimeInterval(-86400 * 15),
            modifiedDate: Date().addingTimeInterval(-86400 * 2),
            isFolder: false,
            mimeType: "text/plain",
            thumbnailData: nil
        ),
        VaultFileEntry(
            id: UUID(),
            name: "Medical Records",
            originalExtension: "",
            size: 0,
            offset: 0,
            nonce: Data(repeating: 0, count: 12),
            parentFolderID: nil,
            createdDate: Date().addingTimeInterval(-86400 * 60),
            modifiedDate: Date().addingTimeInterval(-86400 * 10),
            isFolder: true,
            mimeType: nil,
            thumbnailData: nil
        ),
        VaultFileEntry(
            id: UUID(),
            name: "Bitcoin Wallet Backup",
            originalExtension: "dat",
            size: 850_000,
            offset: 0,
            nonce: Data(repeating: 0, count: 12),
            parentFolderID: nil,
            createdDate: Date().addingTimeInterval(-86400 * 120),
            modifiedDate: Date().addingTimeInterval(-86400 * 120),
            isFolder: false,
            mimeType: "application/octet-stream",
            thumbnailData: nil
        )
    ]

    // MARK: - Lifecycle

    public init() {}

    // MARK: - VaultEncryptionEngine

    public func createVault(name: String, password: String, at path: URL, touchIDEnabled: Bool) async throws -> VaultInfo {
        try await Task.sleep(for: .milliseconds(500))
        return VaultInfo(
            id: UUID(),
            name: name,
            containerPath: path.appendingPathComponent("\(name).vault").path,
            createdDate: Date(),
            touchIDEnabled: touchIDEnabled,
            isDecoy: false
        )
    }

    public func unlockVault(at path: URL, password: String) async throws -> VaultMetadata {
        try await Task.sleep(for: .milliseconds(800))

        guard password == "test" || password == "password" else {
            throw VaultError.wrongPassword
        }

        unlockedVaults.insert(path)
        return MockVaultEngine.makeSampleMetadata(name: path.deletingPathExtension().lastPathComponent)
    }

    public func unlockVaultWithTouchID(at path: URL) async throws -> VaultMetadata {
        try await Task.sleep(for: .milliseconds(600))
        unlockedVaults.insert(path)
        return MockVaultEngine.makeSampleMetadata(name: path.deletingPathExtension().lastPathComponent)
    }

    public func lockVault(at path: URL) async throws {
        try await Task.sleep(for: .milliseconds(300))
        unlockedVaults.remove(path)
    }

    public func addFile(at sourceURL: URL, to vaultPath: URL, parentFolderID: UUID?, secureDeleteOriginal: Bool) async throws -> VaultFileEntry {
        try await Task.sleep(for: .milliseconds(400))
        let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let size = attrs?[.size] as? UInt64 ?? 0

        return VaultFileEntry(
            id: UUID(),
            name: sourceURL.deletingPathExtension().lastPathComponent,
            originalExtension: sourceURL.pathExtension,
            size: size,
            offset: 0,
            nonce: Data(repeating: 0, count: 12),
            parentFolderID: parentFolderID,
            createdDate: Date(),
            modifiedDate: Date(),
            isFolder: false,
            mimeType: nil,
            thumbnailData: nil
        )
    }

    public func removeFile(id: UUID, from vaultPath: URL) async throws {
        try await Task.sleep(for: .milliseconds(200))
    }

    public func readFile(id: UUID, from vaultPath: URL) async throws -> URL {
        try await Task.sleep(for: .milliseconds(300))
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tempFile.path, contents: Data("Mock decrypted content".utf8))
        return tempFile
    }

    public func readFileToMemory(id: UUID, from vaultPath: URL) async throws -> Data {
        try await Task.sleep(for: .milliseconds(200))
        return Data("Mock decrypted content for preview".utf8)
    }

    public func exportFile(id: UUID, from vaultPath: URL, to destinationURL: URL) async throws {
        try await Task.sleep(for: .milliseconds(500))
        try Data("Mock exported content".utf8).write(to: destinationURL)
    }

    public func createFolder(name: String, in vaultPath: URL, parentFolderID: UUID?) async throws -> VaultFileEntry {
        try await Task.sleep(for: .milliseconds(200))
        return VaultFileEntry(
            id: UUID(),
            name: name,
            originalExtension: "",
            size: 0,
            offset: 0,
            nonce: Data(repeating: 0, count: 12),
            parentFolderID: parentFolderID,
            createdDate: Date(),
            modifiedDate: Date(),
            isFolder: true,
            mimeType: nil,
            thumbnailData: nil
        )
    }

    public func getMetadata(for vaultPath: URL) async throws -> VaultMetadata {
        return MockVaultEngine.makeSampleMetadata(name: vaultPath.deletingPathExtension().lastPathComponent)
    }

    public func updateMetadata(_ metadata: VaultMetadata, for vaultPath: URL) async throws {
        try await Task.sleep(for: .milliseconds(200))
    }

    // MARK: - Helpers

    public static func makeSampleMetadata(name: String) -> VaultMetadata {
        VaultMetadata(
            vaultName: name,
            createdDate: Date().addingTimeInterval(-86400 * 60),
            lastModifiedDate: Date(),
            files: sampleFiles,
            touchIDEnabled: true,
            autoLockInterval: .fiveMinutes,
            hasDecoyVault: false,
            decoyFiles: nil,
            failedAttemptCount: 0,
            lastFailedAttemptDate: nil,
            wipeAfterMaxAttempts: false,
            maxFailedAttempts: 10
        )
    }
}
