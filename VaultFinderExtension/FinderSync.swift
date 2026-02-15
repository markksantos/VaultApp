// FinderSync.swift
// VaultFinderExtension
//
// Finder Sync extension providing "Add to Vault" context menu and toolbar integration.

import Cocoa
import FinderSync

class FinderSync: FIFinderSync {

    // MARK: - Properties

    /// Directories to monitor — updated when known vaults change.
    private var monitoredDirectories: Set<URL> = []

    // MARK: - Lifecycle

    override init() {
        super.init()

        // Default: monitor the user's home directory so the context menu
        // appears everywhere. In production, this could be scoped to specific
        // directories via the main app's settings.
        if let homeURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            FIFinderSyncController.default().directoryURLs = [homeURL]
        }
    }

    // MARK: - FIFinderSync Overrides

    override func beginObservingDirectory(at url: URL) {
        // Called when Finder navigates into a monitored directory.
        // Could be used to update badge states on vault files.
    }

    override func endObservingDirectory(at url: URL) {
        // Called when Finder navigates away from a monitored directory.
    }

    override func requestBadgeIdentifier(for url: URL) {
        // Badge vault container files with a lock icon
        if url.pathExtension == "vault" {
            FIFinderSyncController.default().setBadgeIdentifier("locked", for: url)
        }
    }

    // MARK: - Toolbar

    override var toolbarItemName: String {
        return "Vault"
    }

    override var toolbarItemToolTip: String {
        return "Add selected files to a Vault"
    }

    override var toolbarItemImage: NSImage {
        return NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "Vault") ?? NSImage()
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "Vault")

        switch menuKind {
        case .contextualMenuForItems:
            let addItem = NSMenuItem(
                title: "Add to Vault",
                action: #selector(addToVaultAction(_:)),
                keyEquivalent: ""
            )
            addItem.image = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil)
            menu.addItem(addItem)

        case .toolbarItemMenu:
            let addItem = NSMenuItem(
                title: "Add Selected to Vault",
                action: #selector(addToVaultAction(_:)),
                keyEquivalent: ""
            )
            menu.addItem(addItem)

        case .contextualMenuForContainer:
            // No action for container-level context menu
            break

        case .contextualMenuForSidebar:
            break

        @unknown default:
            break
        }

        return menu
    }

    // MARK: - Actions

    @objc private func addToVaultAction(_ sender: Any?) {
        guard let items = FIFinderSyncController.default().selectedItemURLs(), !items.isEmpty else {
            return
        }

        // Communicate selected file URLs to the main Vault app via XPC or URL scheme.
        // The main app handles vault selection, encryption, and optional original deletion.
        launchMainAppWithFiles(items)
    }

    // MARK: - App Communication

    /// Launch the main Vault app and pass selected file URLs for import.
    private func launchMainAppWithFiles(_ urls: [URL]) {
        // Use a custom URL scheme to communicate with the main app.
        // Format: vault://add?files=<encoded-paths>
        let paths = urls.map { $0.path }
        guard let pathData = try? JSONEncoder().encode(paths),
              let pathString = String(data: pathData, encoding: .utf8)?
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return
        }

        let urlString = "vault://add?files=\(pathString)"
        guard let appURL = URL(string: urlString) else { return }

        NSWorkspace.shared.open(appURL)
    }
}
