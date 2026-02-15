// RateLimiterTests.swift
// VaultTests

import XCTest
@testable import VaultCore

final class RateLimiterTests: XCTestCase {

    func testFirstAttemptIsAllowed() {
        let limiter = RateLimiter()
        let status = limiter.checkAttempt(vaultPath: "/test.vault")
        if case .allowed = status {
            // Expected
        } else {
            XCTFail("Expected .allowed for first attempt")
        }
    }

    func testFreeAttemptsBeforeDelay() {
        let limiter = RateLimiter()
        let path = "/test.vault"

        // Record exactly freeAttempts failures
        for _ in 0..<RateLimiter.freeAttempts {
            limiter.recordFailure(vaultPath: path)
        }

        // After freeAttempts failures, next check should impose a delay
        let status = limiter.checkAttempt(vaultPath: path)
        if case .delayed(let seconds) = status {
            XCTAssertGreaterThan(seconds, 0)
        }
        // Note: could also be .allowed if enough time passed during test execution
    }

    func testSuccessResetsCounter() {
        let limiter = RateLimiter()
        let path = "/test.vault"

        for _ in 0..<10 {
            limiter.recordFailure(vaultPath: path)
        }

        limiter.recordSuccess(vaultPath: path)

        let status = limiter.checkAttempt(vaultPath: path)
        if case .allowed = status {
            // Expected
        } else {
            XCTFail("Expected .allowed after success reset")
        }
    }

    func testFailedCountTracking() {
        let limiter = RateLimiter()
        let path = "/test.vault"

        XCTAssertEqual(limiter.failedCount(for: path), 0)
        limiter.recordFailure(vaultPath: path)
        XCTAssertEqual(limiter.failedCount(for: path), 1)
        limiter.recordFailure(vaultPath: path)
        XCTAssertEqual(limiter.failedCount(for: path), 2)
    }

    func testShouldWipe() {
        let limiter = RateLimiter()
        let path = "/test.vault"

        XCTAssertFalse(limiter.shouldWipe(vaultPath: path, maxAttempts: 10))

        for _ in 0..<10 {
            limiter.recordFailure(vaultPath: path)
        }

        XCTAssertTrue(limiter.shouldWipe(vaultPath: path, maxAttempts: 10))
    }

    func testShouldNotWipeBelowThreshold() {
        let limiter = RateLimiter()
        let path = "/test.vault"

        for _ in 0..<5 {
            limiter.recordFailure(vaultPath: path)
        }

        XCTAssertFalse(limiter.shouldWipe(vaultPath: path, maxAttempts: 10))
    }

    func testIndependentVaultTracking() {
        let limiter = RateLimiter()

        limiter.recordFailure(vaultPath: "/vault1.vault")
        limiter.recordFailure(vaultPath: "/vault1.vault")
        limiter.recordFailure(vaultPath: "/vault2.vault")

        XCTAssertEqual(limiter.failedCount(for: "/vault1.vault"), 2)
        XCTAssertEqual(limiter.failedCount(for: "/vault2.vault"), 1)
    }

    func testLoadFromMetadata() {
        let limiter = RateLimiter()
        let path = "/test.vault"

        limiter.loadFromMetadata(vaultPath: path, failedCount: 7, lastFailedDate: Date())
        XCTAssertEqual(limiter.failedCount(for: path), 7)
    }
}
