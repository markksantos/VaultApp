// KeyDerivationTests.swift
// VaultTests

import XCTest
import CryptoKit
@testable import VaultCore

final class KeyDerivationTests: XCTestCase {

    private let fastParams = KeyDerivationParams(
        algorithm: .pbkdf2HMACSHA256,
        iterations: 1000, // low count for test speed
        memory: 0,
        saltLength: 32,
        keyLength: 32
    )

    func testDeriveKeyProducesDeterministicOutput() throws {
        let password = "TestPassword123!"
        let salt = Data(repeating: 0xAB, count: 32)

        let key1 = try KeyDerivationService.deriveKey(password: password, salt: salt, params: fastParams)
        let key2 = try KeyDerivationService.deriveKey(password: password, salt: salt, params: fastParams)

        let data1 = key1.withUnsafeBytes { Data($0) }
        let data2 = key2.withUnsafeBytes { Data($0) }
        XCTAssertEqual(data1, data2, "Same password + salt should produce identical keys")
    }

    func testDifferentPasswordsProduceDifferentKeys() throws {
        let salt = Data(repeating: 0xAB, count: 32)

        let key1 = try KeyDerivationService.deriveKey(password: "password1", salt: salt, params: fastParams)
        let key2 = try KeyDerivationService.deriveKey(password: "password2", salt: salt, params: fastParams)

        let data1 = key1.withUnsafeBytes { Data($0) }
        let data2 = key2.withUnsafeBytes { Data($0) }
        XCTAssertNotEqual(data1, data2)
    }

    func testDifferentSaltsProduceDifferentKeys() throws {
        let key1 = try KeyDerivationService.deriveKey(
            password: "password",
            salt: Data(repeating: 0x01, count: 32),
            params: fastParams
        )
        let key2 = try KeyDerivationService.deriveKey(
            password: "password",
            salt: Data(repeating: 0x02, count: 32),
            params: fastParams
        )

        let data1 = key1.withUnsafeBytes { Data($0) }
        let data2 = key2.withUnsafeBytes { Data($0) }
        XCTAssertNotEqual(data1, data2)
    }

    func testGenerateSaltHasCorrectLength() {
        let salt = KeyDerivationService.generateSalt(length: 32)
        XCTAssertEqual(salt.count, 32)
    }

    func testGenerateSaltIsRandom() {
        let salt1 = KeyDerivationService.generateSalt()
        let salt2 = KeyDerivationService.generateSalt()
        XCTAssertNotEqual(salt1, salt2)
    }

    func testArgon2idThrows() {
        let params = KeyDerivationParams(
            algorithm: .argon2id,
            iterations: 1,
            memory: 65536,
            saltLength: 32,
            keyLength: 32
        )

        XCTAssertThrowsError(try KeyDerivationService.deriveKey(
            password: "test", salt: Data(count: 32), params: params
        ))
    }

    func testDerivedKeyIs256Bits() throws {
        let salt = KeyDerivationService.generateSalt()
        let key = try KeyDerivationService.deriveKey(password: "test", salt: salt, params: fastParams)
        let keyData = key.withUnsafeBytes { Data($0) }
        XCTAssertEqual(keyData.count, 32, "Key should be 256 bits (32 bytes)")
    }
}
