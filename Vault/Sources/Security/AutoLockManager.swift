// AutoLockManager.swift
// Vault
//
// Timer-based auto-lock with system event integration (screen lock, sleep).

import Foundation
import AppKit

/// Manages automatic vault locking based on configured intervals and system events.
@MainActor
public final class AutoLockManager {

    // MARK: - Properties

    private var timer: Timer?
    private var interval: AutoLockInterval = .onScreenLock
    private var lockAction: (() async -> Void)?

    private var screenLockObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var screenUnlockObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    public init() {}

    // Cleanup is handled via configure() -> restartMonitoring() lifecycle.
    // deinit cannot call @MainActor methods, so callers must call stopMonitoring() explicitly.

    // MARK: - Configuration

    /// Configure the auto-lock manager with an interval and lock action.
    /// - Parameters:
    ///   - interval: The auto-lock interval from vault settings.
    ///   - lockAction: Closure invoked to lock all open vaults.
    public func configure(interval: AutoLockInterval, lockAction: @escaping () async -> Void) {
        self.interval = interval
        self.lockAction = lockAction
        restartMonitoring()
    }

    /// Update the auto-lock interval without changing the lock action.
    public func updateInterval(_ newInterval: AutoLockInterval) {
        self.interval = newInterval
        restartMonitoring()
    }

    // MARK: - Timer Management

    /// Reset the inactivity timer. Call this on meaningful user interaction.
    public func resetTimer() {
        guard let seconds = interval.timeInterval else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.triggerLock()
            }
        }
    }

    // MARK: - Monitoring

    private func restartMonitoring() {
        stopMonitoring()
        startMonitoring()
    }

    private func startMonitoring() {
        let workspace = NSWorkspace.shared.notificationCenter

        // Always observe screen lock — locks vault regardless of interval setting
        if interval == .onScreenLock || interval == .onSleep {
            screenLockObserver = workspace.addObserver(
                forName: NSNotification.Name("com.apple.screenIsLocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.triggerLock()
                }
            }
        }

        if interval == .onSleep {
            sleepObserver = workspace.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.triggerLock()
                }
            }
        }

        // Start inactivity timer for timed intervals
        if interval.timeInterval != nil {
            resetTimer()
        }
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil

        let workspace = NSWorkspace.shared.notificationCenter
        if let observer = screenLockObserver {
            workspace.removeObserver(observer)
            screenLockObserver = nil
        }
        if let observer = sleepObserver {
            workspace.removeObserver(observer)
            sleepObserver = nil
        }
        if let observer = screenUnlockObserver {
            workspace.removeObserver(observer)
            screenUnlockObserver = nil
        }
    }

    // MARK: - Lock Trigger

    private func triggerLock() async {
        timer?.invalidate()
        timer = nil
        await lockAction?()
    }
}
