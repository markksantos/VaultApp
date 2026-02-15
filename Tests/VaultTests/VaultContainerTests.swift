// VaultContainerTests.swift
// VaultTests

import XCTest
import CryptoKit
@testable import VaultCore

final class VaultContainerTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaultContainerTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testHeaderSerializationRoundTrip() throws {
        let header = VaultContainerHeader(
            magic: [0x56, 0x4C, 0x54, 0x58],
            version: 1,
            salt: Data(repeating: 0xAA, count: 32),
            metadataNonce: Data(repeating: 0xBB, count: 12),
            metadataLength: 256,
            kdfAlgorithm: .pbkdf2HMACSHA256,
            kdfIterations: 600_000,
            kdfMemory: 0
        )

        let serialized = VaultContainer.serializeHeader(header)
        XCTAssertEqual(serialized.count, VaultContainerHeader.fixedSize)

        let deserialized = try VaultContainer.deserializeHeader(serialized)
        XCTAssertEqual(deserialized.magic, header.magic)
        XCTAssertEqual(deserialized.version, header.version)
        XCTAssertEqual(deserialized.salt, header.salt)
        XCTAssertEqual(deserialized.metadataNonce, header.metadataNonce)
        XCTAssertEqual(deserialized.metadataLength, header.metadataLength)
        XCTAssertEqual(deserialized.kdfAlgorithm, header.kdfAlgorithm)
        XCTAssertEqual(deserialized.kdfIterations, header.kdfIterations)
        XCTAssertEqual(deserialized.kdfMemory, header.kdfMemory)
    }

    func testHeaderFixedSizeIs67() {
        XCTAssertEqual(VaultContainerHeader.fixedSize, 67)
    }

    func testInvalidMagicBytesThrows() {
        var data = Data(count: VaultContainerHeader.fixedSize)
        data[0] = 0xFF // wrong magic
        data[1] = 0xFF
        data[2] = 0xFF
        data[3] = 0xFF

        XCTAssertThrowsError(try VaultContainer.deserializeHeader(data))
    }

    func testCreateAndReadContainer() throws {
        let key = SymmetricKey(size: .bits256)
        let containerURL = tempDir.appendingPathComponent("test.vault")

        let metadata = VaultMetadata(
            vaultName: "Test",
            createdDate: Date(),
            lastModifiedDate: Date(),
            files: [],
            touchIDEnabled: false,
            autoLockInterval: .fiveMinutes,
            hasDecoyVault: false,
            decoyFiles: nil,
            failedAttemptCount: 0,
            lastFailedAttemptDate: nil,
            wipeAfterMaxAttempts: false,
            maxFailedAttempts: 10
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(metadata)
        let (encryptedMetadata, nonce) = try AESEncryptor.encrypt(data: jsonData, key: key)

        let header = VaultContainerHeader(
            magic: [0x56, 0x4C, 0x54, 0x58],
            version: 1,
            salt: Data(repeating: 0xAA, count: 32),
            metadataNonce: nonce,
            metadataLength: UInt64(encryptedMetadata.count),
            kdfAlgorithm: .pbkdf2HMACSHA256,
            kdfIterations: 600_000,
            kdfMemory: 0
        )

        try VaultContainer.createContainer(at: containerURL, header: header, encryptedMetadata: encryptedMetadata)

        // Read header back
        let readHeader = try VaultContainer.readHeader(at: containerURL)
        XCTAssertEqual(readHeader.version, 1)
        XCTAssertEqual(readHeader.metadataLength, UInt64(encryptedMetadata.count))

        // Read and decrypt metadata back
        let readMetadata = try VaultContainer.readMetadata(at: containerURL, key: key)
        XCTAssertEqual(readMetadata.vaultName, "Test")
        XCTAssertEqual(readMetadata.files.count, 0)
    }

    func testReadHeaderFromMissingFileThrows() {
        let badURL = tempDir.appendingPathComponent("nonexistent.vault")
        XCTAssertThrowsError(try VaultContainer.readHeader(at: badURL))
    }

    func testAppendAndReadFileBlock() throws {
        let key = SymmetricKey(size: .bits256)
        let containerURL = tempDir.appendingPathComponent("test.vault")

        // Create a container first
        let metadata = VaultMetadata(
            vaultName: "Test",
            createdDate: Date(),
            lastModifiedDate: Date(),
            files: [],
            touchIDEnabled: false,
            autoLockInterval: .fiveMinutes,
            hasDecoyVault: false,
            decoyFiles: nil,
            failedAttemptCount: 0,
            lastFailedAttemptDate: nil,
            wipeAfterMaxAttempts: false,
            maxFailedAttempts: 10
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(metadata)
        let (encryptedMetadata, nonce) = try AESEncryptor.encrypt(data: jsonData, key: key)

        let header = VaultContainerHeader(
            magic: [0x56, 0x4C, 0x54, 0x58],
            version: 1,
            salt: Data(repeating: 0xAA, count: 32),
            metadataNonce: nonce,
            metadataLength: UInt64(encryptedMetadata.count),
            kdfAlgorithm: .pbkdf2HMACSHA256,
            kdfIterations: 600_000,
            kdfMemory: 0
        )

        try VaultContainer.createContainer(at: containerURL, header: header, encryptedMetadata: encryptedMetadata)

        // Append a file block
        let testData = Data("encrypted file content".utf8)
        let offset = try VaultContainer.appendFileBlock(encryptedData: testData, to: containerURL, header: header)
        XCTAssertEqual(offset, 0, "First file block should be at offset 0")

        // Read it back
        let readData = try VaultContainer.readFileBlock(
            at: containerURL,
            header: header,
            offset: offset,
            size: UInt64(testData.count)
        )
        XCTAssertEqual(readData, testData)
    }
}
