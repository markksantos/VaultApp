// TempFileManager.swift
// Vault
//
// Track and auto-cleanup temporary decrypted files.

import Foundation
import AppKit
import os

/// Manages temporary decrypted files created when opening vault contents
/// in external applications. Ensures no decrypted data persists on disk.
public final class TempFileManager {

    // MARK: - Types

    private struct TrackedFile {
        let url: URL
        let vaultPath: String
        let createdAt: Date
    }

    // MARK: - Properties

    /// Default auto-cleanup timeout in seconds.
    public static let defaultTimeout: TimeInterval = 300 // 5 minutes

    private let trackedFiles = OSAllocatedUnfairLock(initialState: [TrackedFile]())
    private var cleanupTimer: Timer?
    private var timeout: TimeInterval

    // MARK: - Lifecycle

    public init(timeout: TimeInterval = TempFileManager.defaultTimeout) {
        self.timeout = timeout
        startCleanupTimer()
        registerForTermination()
    }

    deinit {
        cleanupTimer?.invalidate()
        cleanupAllSync()
    }

    // MARK: - Tracking

    /// Register a temporary decrypted file for tracking and auto-cleanup.
    /// - Parameters:
    ///   - url: The temporary file URL.
    ///   - vaultPath: The vault container path this file belongs to.
    public func trackFile(at url: URL, vaultPath: String) {
        trackedFiles.withLock { $0.append(TrackedFile(url: url, vaultPath: vaultPath, createdAt: Date())) }
    }

    /// Remove tracking for a specific file (e.g., if user explicitly closed it).
    public func untrackFile(at url: URL) {
        trackedFiles.withLock { $0.removeAll { $0.url == url } }
    }

    // MARK: - Cleanup

    /// Clean up all temp files associated with a specific vault.
    /// Called when a vault is locked.
    public func cleanupFiles(for vaultPath: String) {
        let filesToClean = trackedFiles.withLock { state -> [TrackedFile] in
            let files = state.filter { $0.vaultPath == vaultPath }
            state.removeAll { $0.vaultPath == vaultPath }
            return files
        }

        for file in filesToClean {
            secureDeleteQuietly(at: file.url)
        }
    }

    /// Clean up all tracked temp files regardless of vault.
    public func cleanupAll() {
        let allFiles = trackedFiles.withLock { state -> [TrackedFile] in
            let files = state
            state.removeAll()
            return files
        }

        for file in allFiles {
            secureDeleteQuietly(at: file.url)
        }
    }

    /// Clean up expired temp files (past timeout).
    public func cleanupExpired() {
        let now = Date()

        let expired = trackedFiles.withLock { state -> [TrackedFile] in
            let expiredFiles = state.filter { now.timeIntervalSince($0.createdAt) >= timeout }
            state.removeAll { file in
                expiredFiles.contains { $0.url == file.url }
            }
            return expiredFiles
        }

        for file in expired {
            secureDeleteQuietly(at: file.url)
        }
    }

    /// Get the number of currently tracked temp files.
    public var trackedFileCount: Int {
        trackedFiles.withLock { $0.count }
    }

    /// Update the auto-cleanup timeout.
    public func updateTimeout(_ newTimeout: TimeInterval) {
        self.timeout = newTimeout
    }

    // MARK: - Private

    private func startCleanupTimer() {
        // Check for expired files every 30 seconds
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.cleanupExpired()
        }
    }

    private func registerForTermination() {
        // On app termination, aggressively clean all temp files
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cleanupAllSync()
        }
    }

    /// Synchronous cleanup for use during app termination.
    private func cleanupAllSync() {
        let allFiles = trackedFiles.withLock { state -> [TrackedFile] in
            let files = state
            state.removeAll()
            return files
        }

        for file in allFiles {
            secureDeleteQuietly(at: file.url)
        }
    }

    private func secureDeleteQuietly(at url: URL) {
        do {
            try SecureDeleteService.secureDelete(at: url)
        } catch {
            // Fallback: regular delete if secure delete fails
            try? FileManager.default.removeItem(at: url)
        }
    }
}
