// VaultEngineIntegrationTests.swift
// VaultTests

import XCTest
@testable import VaultCore

final class VaultEngineIntegrationTests: XCTestCase {

    private var tempDir: URL!
    private var engine: VaultEngine!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaultEngineTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        engine = VaultEngine()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testCreateVault() async throws {
        let vaultPath = tempDir.appendingPathComponent("test.vault")
        let password = "StrongP@ssw0rd!"

        let vaultInfo = try await engine.createVault(
            name: "Test Vault",
            password: password,
            at: vaultPath,
            touchIDEnabled: false
        )

        XCTAssertEqual(vaultInfo.name, "Test Vault")
        XCTAssertTrue(FileManager.default.fileExists(atPath: vaultPath.path))
    }

    func testLockAndUnlock() async throws {
        let vaultPath = tempDir.appendingPathComponent("test.vault")
        let password = "StrongP@ssw0rd!"

        _ = try await engine.createVault(
            name: "Test Vault",
            password: password,
            at: vaultPath,
            touchIDEnabled: false
        )

        // Lock
        try await engine.lockVault(at: vaultPath)

        // Unlock
        let metadata = try await engine.unlockVault(at: vaultPath, password: password)
        XCTAssertEqual(metadata.vaultName, "Test Vault")
        XCTAssertEqual(metadata.files.count, 0)
    }

    func testWrongPasswordThrows() async throws {
        let vaultPath = tempDir.appendingPathComponent("test.vault")

        _ = try await engine.createVault(
            name: "Test", password: "correct", at: vaultPath, touchIDEnabled: false
        )
        try await engine.lockVault(at: vaultPath)

        do {
            _ = try await engine.unlockVault(at: vaultPath, password: "wrong")
            XCTFail("Expected wrongPassword error")
        } catch let error as VaultError {
            if case .wrongPassword = error {
                // Expected
            } else {
                XCTFail("Expected .wrongPassword, got \(error)")
            }
        }
    }

    func testAddAndExportFile() async throws {
        let vaultPath = tempDir.appendingPathComponent("test.vault")
        let password = "Test123!"

        _ = try await engine.createVault(
            name: "Test", password: password, at: vaultPath, touchIDEnabled: false
        )

        // Create a test file
        let testFileURL = tempDir.appendingPathComponent("testfile.txt")
        let originalContent = Data("Hello, encrypted world!".utf8)
        try originalContent.write(to: testFileURL)

        // Add file
        let entry = try await engine.addFile(
            at: testFileURL, to: vaultPath, parentFolderID: nil, secureDeleteOriginal: false
        )
        XCTAssertEqual(entry.name, "testfile.txt")
        XCTAssertFalse(entry.isFolder)

        // Export file
        let exportURL = tempDir.appendingPathComponent("exported.txt")
        try await engine.exportFile(id: entry.id, from: vaultPath, to: exportURL)

        let exportedContent = try Data(contentsOf: exportURL)
        XCTAssertEqual(originalContent, exportedContent, "Exported content should match original")
    }

    func testAddFileAndReadToMemory() async throws {
        let vaultPath = tempDir.appendingPathComponent("test.vault")

        _ = try await engine.createVault(
            name: "Test", password: "Test123!", at: vaultPath, touchIDEnabled: false
        )

        let testFileURL = tempDir.appendingPathComponent("memory.txt")
        let originalContent = Data("Memory test content".utf8)
        try originalContent.write(to: testFileURL)

        let entry = try await engine.addFile(
            at: testFileURL, to: vaultPath, parentFolderID: nil, secureDeleteOriginal: false
        )

        let memoryData = try await engine.readFileToMemory(id: entry.id, from: vaultPath)
        XCTAssertEqual(memoryData, originalContent)
    }

    func testCreateAndListFolders() async throws {
        let vaultPath = tempDir.appendingPathComponent("test.vault")

        _ = try await engine.createVault(
            name: "Test", password: "Test123!", at: vaultPath, touchIDEnabled: false
        )

        let folder = try await engine.createFolder(
            name: "Documents", in: vaultPath, parentFolderID: nil
        )
        XCTAssertTrue(folder.isFolder)
        XCTAssertEqual(folder.name, "Documents")

        let metadata = try await engine.getMetadata(for: vaultPath)
        XCTAssertEqual(metadata.files.count, 1)
        XCTAssertTrue(metadata.files[0].isFolder)
    }

    func testRemoveFile() async throws {
        let vaultPath = tempDir.appendingPathComponent("test.vault")

        _ = try await engine.createVault(
            name: "Test", password: "Test123!", at: vaultPath, touchIDEnabled: false
        )

        let testFileURL = tempDir.appendingPathComponent("remove.txt")
        try Data("to be removed".utf8).write(to: testFileURL)

        let entry = try await engine.addFile(
            at: testFileURL, to: vaultPath, parentFolderID: nil, secureDeleteOriginal: false
        )

        var metadata = try await engine.getMetadata(for: vaultPath)
        XCTAssertEqual(metadata.files.count, 1)

        try await engine.removeFile(id: entry.id, from: vaultPath)

        metadata = try await engine.getMetadata(for: vaultPath)
        XCTAssertEqual(metadata.files.count, 0, "File should be removed from metadata")
    }

    func testFilesPersistAcrossLockUnlock() async throws {
        let vaultPath = tempDir.appendingPathComponent("test.vault")
        let password = "Test123!"

        _ = try await engine.createVault(
            name: "Test", password: password, at: vaultPath, touchIDEnabled: false
        )

        // Add a file
        let testFileURL = tempDir.appendingPathComponent("persist.txt")
        let originalContent = Data("Persistent data".utf8)
        try originalContent.write(to: testFileURL)

        let entry = try await engine.addFile(
            at: testFileURL, to: vaultPath, parentFolderID: nil, secureDeleteOriginal: false
        )

        // Lock and re-unlock
        try await engine.lockVault(at: vaultPath)
        let metadata = try await engine.unlockVault(at: vaultPath, password: password)

        XCTAssertEqual(metadata.files.count, 1)
        XCTAssertEqual(metadata.files[0].name, "persist.txt")

        // Verify content is still correct
        let readData = try await engine.readFileToMemory(id: entry.id, from: vaultPath)
        XCTAssertEqual(readData, originalContent)
    }

    func testMultipleFiles() async throws {
        let vaultPath = tempDir.appendingPathComponent("test.vault")

        _ = try await engine.createVault(
            name: "Test", password: "Test123!", at: vaultPath, touchIDEnabled: false
        )

        // Add 3 files
        for i in 1...3 {
            let fileURL = tempDir.appendingPathComponent("file\(i).txt")
            try Data("Content \(i)".utf8).write(to: fileURL)
            _ = try await engine.addFile(
                at: fileURL, to: vaultPath, parentFolderID: nil, secureDeleteOriginal: false
            )
        }

        let metadata = try await engine.getMetadata(for: vaultPath)
        XCTAssertEqual(metadata.files.count, 3)
    }

    func testSecureDeleteOriginal() async throws {
        let vaultPath = tempDir.appendingPathComponent("test.vault")

        _ = try await engine.createVault(
            name: "Test", password: "Test123!", at: vaultPath, touchIDEnabled: false
        )

        let testFileURL = tempDir.appendingPathComponent("delete-me.txt")
        try Data("secret data".utf8).write(to: testFileURL)

        _ = try await engine.addFile(
            at: testFileURL, to: vaultPath, parentFolderID: nil, secureDeleteOriginal: true
        )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: testFileURL.path),
            "Original file should be securely deleted"
        )
    }
}
