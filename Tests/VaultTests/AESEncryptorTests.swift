// AESEncryptorTests.swift
// VaultTests

import XCTest
import CryptoKit
@testable import VaultCore

final class AESEncryptorTests: XCTestCase {

    func testEncryptDecryptRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("Hello, Vault!".utf8)

        let (ciphertext, nonce) = try AESEncryptor.encrypt(data: plaintext, key: key)
        let decrypted = try AESEncryptor.decrypt(ciphertext: ciphertext, nonce: nonce, key: key)

        XCTAssertEqual(plaintext, decrypted)
    }

    func testEncryptProducesDifferentCiphertextEachTime() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("Same input".utf8)

        let (ct1, _) = try AESEncryptor.encrypt(data: plaintext, key: key)
        let (ct2, _) = try AESEncryptor.encrypt(data: plaintext, key: key)

        XCTAssertNotEqual(ct1, ct2, "Different nonces should produce different ciphertext")
    }

    func testDecryptWithWrongKeyFails() throws {
        let key1 = SymmetricKey(size: .bits256)
        let key2 = SymmetricKey(size: .bits256)
        let plaintext = Data("Secret".utf8)

        let (ciphertext, nonce) = try AESEncryptor.encrypt(data: plaintext, key: key1)

        XCTAssertThrowsError(try AESEncryptor.decrypt(ciphertext: ciphertext, nonce: nonce, key: key2))
    }

    func testEncryptEmptyData() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data()

        let (ciphertext, nonce) = try AESEncryptor.encrypt(data: plaintext, key: key)
        let decrypted = try AESEncryptor.decrypt(ciphertext: ciphertext, nonce: nonce, key: key)

        XCTAssertEqual(plaintext, decrypted)
    }

    func testNonceIs12Bytes() throws {
        let key = SymmetricKey(size: .bits256)
        let (_, nonce) = try AESEncryptor.encrypt(data: Data("test".utf8), key: key)
        XCTAssertEqual(nonce.count, 12)
    }

    func testLargeDataRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data(repeating: 0xAB, count: 1_000_000) // 1 MB

        let (ciphertext, nonce) = try AESEncryptor.encrypt(data: plaintext, key: key)
        let decrypted = try AESEncryptor.decrypt(ciphertext: ciphertext, nonce: nonce, key: key)

        XCTAssertEqual(plaintext, decrypted)
    }

    func testCiphertextIncludesGCMTag() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("test".utf8)

        let (ciphertext, _) = try AESEncryptor.encrypt(data: plaintext, key: key)

        // Ciphertext should be plaintext length + 16-byte GCM tag
        XCTAssertEqual(ciphertext.count, plaintext.count + 16)
    }
}
