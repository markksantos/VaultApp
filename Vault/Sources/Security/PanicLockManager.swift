// PanicLockManager.swift
// Vault
//
// Global hotkey for instant vault locking — silent, no animation.

import Foundation
import AppKit
import Carbon.HIToolbox

/// Manages a global keyboard shortcut that immediately locks all vaults.
/// Default shortcut: Cmd+Shift+L. Configurable via AppSettings.
public final class PanicLockManager {

    // MARK: - Properties

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lockAction: (() async -> Void)?
    private var shortcutModifiers: NSEvent.ModifierFlags = [.command, .shift]
    private var shortcutKeyCode: UInt16 = UInt16(kVK_ANSI_L)

    // MARK: - Lifecycle

    public init() {}

    deinit {
        unregister()
    }

    // MARK: - Configuration

    /// Register the panic lock shortcut.
    /// - Parameters:
    ///   - lockAction: Closure invoked to lock all vaults immediately.
    ///   - keyCode: Virtual key code (default: L).
    ///   - modifiers: Modifier flags (default: Cmd+Shift).
    public func register(
        lockAction: @escaping () async -> Void,
        keyCode: UInt16? = nil,
        modifiers: NSEvent.ModifierFlags? = nil
    ) {
        self.lockAction = lockAction
        if let keyCode { self.shortcutKeyCode = keyCode }
        if let modifiers { self.shortcutModifiers = modifiers }

        // Global monitor — captures shortcut when app is NOT focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Local monitor — captures shortcut when app IS focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.isMatchingShortcut(event) == true {
                self?.handleKeyEvent(event)
                return nil // consume the event
            }
            return event
        }
    }

    /// Unregister the panic lock shortcut.
    public func unregister() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    /// Update the shortcut binding.
    public func updateShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        let action = self.lockAction
        unregister()
        if let action {
            register(lockAction: action, keyCode: keyCode, modifiers: modifiers)
        }
    }

    // MARK: - Event Handling

    private func handleKeyEvent(_ event: NSEvent) {
        guard isMatchingShortcut(event) else { return }
        guard let lockAction else { return }

        // Fire immediately on background queue — no UI, no animation, no sound
        Task {
            await lockAction()
        }
    }

    private func isMatchingShortcut(_ event: NSEvent) -> Bool {
        let relevantModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let eventModifiers = event.modifierFlags.intersection(relevantModifiers)
        let targetModifiers = shortcutModifiers.intersection(relevantModifiers)
        return event.keyCode == shortcutKeyCode && eventModifiers == targetModifiers
    }
}
