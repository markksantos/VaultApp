// RateLimiter.swift
// Vault
//
// Track failed password attempts per vault with escalating delays and optional wipe.

import Foundation
import os

/// Enforces rate limiting on vault unlock attempts.
/// After a threshold of failures, imposes escalating delays.
/// Optionally wipes vault data after a configurable maximum.
public final class RateLimiter {

    // MARK: - Constants

    /// Number of free attempts before delays kick in.
    public static let freeAttempts = 5

    /// Escalating delay schedule (in seconds) after free attempts are exhausted.
    /// Index 0 = 6th attempt, index 1 = 7th attempt, etc.
    /// Beyond the array bounds, the last value is used.
    public static let delaySchedule: [TimeInterval] = [1, 5, 15, 60]

    // MARK: - State

    /// In-memory cache of per-vault attempt tracking, keyed by vault container path.
    private let attempts = OSAllocatedUnfairLock(initialState: [String: AttemptRecord]())

    public struct AttemptRecord {
        public var failedCount: Int
        public var lastFailedDate: Date?

        public init(failedCount: Int, lastFailedDate: Date?) {
            self.failedCount = failedCount
            self.lastFailedDate = lastFailedDate
        }
    }

    // MARK: - Lifecycle

    public init() {}

    // MARK: - Public API

    /// Check whether an unlock attempt is allowed for the given vault.
    /// - Parameter vaultPath: The vault container file path.
    /// - Returns: `.allowed` if the attempt can proceed, or `.delayed(seconds)` with
    ///   the remaining wait time.
    public func checkAttempt(vaultPath: String) -> AttemptStatus {
        attempts.withLock { state in
            guard let record = state[vaultPath] else {
                return .allowed
            }

            let delay = requiredDelay(failedCount: record.failedCount)
            guard delay > 0, let lastFailed = record.lastFailedDate else {
                return .allowed
            }

            let elapsed = Date().timeIntervalSince(lastFailed)
            let remaining = delay - elapsed
            if remaining > 0 {
                return .delayed(seconds: remaining)
            }
            return .allowed
        }
    }

    /// Record a failed unlock attempt.
    /// - Parameter vaultPath: The vault container file path.
    /// - Returns: The updated failed attempt count.
    @discardableResult
    public func recordFailure(vaultPath: String) -> Int {
        attempts.withLock { state in
            var record = state[vaultPath] ?? AttemptRecord(failedCount: 0, lastFailedDate: nil)
            record.failedCount += 1
            record.lastFailedDate = Date()
            state[vaultPath] = record
            return record.failedCount
        }
    }

    /// Record a successful unlock — resets the failure counter.
    public func recordSuccess(vaultPath: String) {
        _ = attempts.withLock { $0.removeValue(forKey: vaultPath) }
    }

    /// Check if the vault has exceeded the maximum allowed attempts.
    /// - Parameters:
    ///   - vaultPath: The vault container file path.
    ///   - maxAttempts: Configurable max (from vault metadata).
    /// - Returns: `true` if the wipe threshold has been reached.
    public func shouldWipe(vaultPath: String, maxAttempts: Int) -> Bool {
        attempts.withLock { state in
            guard let record = state[vaultPath] else { return false }
            return record.failedCount >= maxAttempts
        }
    }

    /// Get the current failed attempt count for a vault.
    public func failedCount(for vaultPath: String) -> Int {
        attempts.withLock { $0[vaultPath]?.failedCount ?? 0 }
    }

    /// Sync state from persisted vault metadata (call on vault load).
    public func loadFromMetadata(vaultPath: String, failedCount: Int, lastFailedDate: Date?) {
        attempts.withLock { state in
            if failedCount > 0 {
                state[vaultPath] = AttemptRecord(failedCount: failedCount, lastFailedDate: lastFailedDate)
            }
        }
    }

    // MARK: - Private

    private func requiredDelay(failedCount: Int) -> TimeInterval {
        let excessAttempts = failedCount - Self.freeAttempts
        guard excessAttempts > 0 else { return 0 }

        let index = min(excessAttempts - 1, Self.delaySchedule.count - 1)
        return Self.delaySchedule[index]
    }
}

// MARK: - AttemptStatus

public extension RateLimiter {
    enum AttemptStatus {
        case allowed
        case delayed(seconds: TimeInterval)
    }
}
