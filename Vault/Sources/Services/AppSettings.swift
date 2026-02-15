// AppSettings.swift
// Vault
//
// UserDefaults-backed application settings.

import Foundation
import AppKit
import Carbon.HIToolbox

/// Centralized app settings backed by UserDefaults.
/// Provides type-safe access to all persistent preferences.
public final class AppSettings: ObservableObject {

    // MARK: - Keys

    private enum Keys {
        static let knownVaults = "vault.knownVaults"
        static let autoLockInterval = "vault.autoLockInterval"
        static let deleteOriginalsDefault = "vault.deleteOriginalsDefault"
        static let licenseTier = "vault.licenseTier"
        static let iCloudSyncEnabled = "vault.iCloudSyncEnabled"
        static let panicShortcutKeyCode = "vault.panicShortcutKeyCode"
        static let panicShortcutModifiers = "vault.panicShortcutModifiers"
        static let tempFileTimeout = "vault.tempFileTimeout"
    }

    // MARK: - Properties

    private let defaults: UserDefaults

    // MARK: - Lifecycle

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.autoLockInterval: AutoLockInterval.onScreenLock.rawValue,
            Keys.deleteOriginalsDefault: false,
            Keys.licenseTier: "free",
            Keys.iCloudSyncEnabled: false,
            Keys.panicShortcutKeyCode: Int(kVK_ANSI_L),
            Keys.panicShortcutModifiers: Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue),
            Keys.tempFileTimeout: TempFileManager.defaultTimeout,
        ])
    }

    // MARK: - Known Vaults

    /// List of known vault containers the user has opened.
    public var knownVaults: [VaultInfo] {
        get {
            guard let data = defaults.data(forKey: Keys.knownVaults) else { return [] }
            return (try? JSONDecoder().decode([VaultInfo].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            defaults.set(data, forKey: Keys.knownVaults)
            objectWillChange.send()
        }
    }

    /// Add a vault to the known vaults list (no duplicates by ID).
    public func addKnownVault(_ vault: VaultInfo) {
        var vaults = knownVaults
        vaults.removeAll { $0.id == vault.id }
        vaults.append(vault)
        knownVaults = vaults
    }

    /// Remove a vault from the known vaults list.
    public func removeKnownVault(id: UUID) {
        var vaults = knownVaults
        vaults.removeAll { $0.id == id }
        knownVaults = vaults
    }

    // MARK: - Auto-Lock

    /// Global auto-lock interval preference.
    public var autoLockInterval: AutoLockInterval {
        get {
            let raw = defaults.string(forKey: Keys.autoLockInterval) ?? AutoLockInterval.onScreenLock.rawValue
            return AutoLockInterval(rawValue: raw) ?? .onScreenLock
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.autoLockInterval)
            objectWillChange.send()
        }
    }

    // MARK: - Delete Originals

    /// Default preference for deleting originals after adding to vault.
    public var deleteOriginalsDefault: Bool {
        get { defaults.bool(forKey: Keys.deleteOriginalsDefault) }
        set {
            defaults.set(newValue, forKey: Keys.deleteOriginalsDefault)
            objectWillChange.send()
        }
    }

    // MARK: - License

    /// Current license tier.
    public var licenseTier: LicenseTier {
        get {
            let raw = defaults.string(forKey: Keys.licenseTier) ?? "free"
            return raw == "paid" ? .paid : .free
        }
        set {
            defaults.set(newValue == .paid ? "paid" : "free", forKey: Keys.licenseTier)
            objectWillChange.send()
        }
    }

    // MARK: - iCloud Sync

    /// Whether iCloud sync is enabled (opt-in, default off).
    public var iCloudSyncEnabled: Bool {
        get { defaults.bool(forKey: Keys.iCloudSyncEnabled) }
        set {
            defaults.set(newValue, forKey: Keys.iCloudSyncEnabled)
            objectWillChange.send()
        }
    }

    // MARK: - Panic Shortcut

    /// Key code for the panic lock shortcut.
    public var panicShortcutKeyCode: UInt16 {
        get { UInt16(defaults.integer(forKey: Keys.panicShortcutKeyCode)) }
        set {
            defaults.set(Int(newValue), forKey: Keys.panicShortcutKeyCode)
            objectWillChange.send()
        }
    }

    /// Modifier flags for the panic lock shortcut.
    public var panicShortcutModifiers: NSEvent.ModifierFlags {
        get { NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: Keys.panicShortcutModifiers))) }
        set {
            defaults.set(Int(newValue.rawValue), forKey: Keys.panicShortcutModifiers)
            objectWillChange.send()
        }
    }

    // MARK: - Temp File Timeout

    /// Timeout for auto-cleanup of temporary decrypted files (seconds).
    public var tempFileTimeout: TimeInterval {
        get { defaults.double(forKey: Keys.tempFileTimeout) }
        set {
            defaults.set(newValue, forKey: Keys.tempFileTimeout)
            objectWillChange.send()
        }
    }
}
