// VaultViewModel.swift
// Vault
//
// Main view model managing vault list, state, selection, search, and drag-drop coordination.

import Foundation
import SwiftUI
import Observation

@Observable
public final class VaultViewModel {

    // MARK: - Dependencies

    private let engine: VaultEncryptionEngine
    private let settings: AppSettings
    private let rateLimiter = RateLimiter()
    private var autoLockManager: AutoLockManager?

    // MARK: - Vault List

    public var vaults: [VaultInfo] = []
    public var selectedVaultID: UUID?

    // MARK: - Vault State

    public var vaultStates: [UUID: VaultState] = [:]
    public var vaultMetadata: [UUID: VaultMetadata] = [:]

    // MARK: - File Selection & Navigation

    public var selectedFileIDs: Set<UUID> = []
    public var currentFolderID: UUID? = nil
    public var navigationPath: [(id: UUID, name: String)] = []

    // MARK: - Search

    public var searchText: String = ""

    // MARK: - View Modes

    public var isGridView: Bool = true
    public var showingCreationWizard: Bool = false
    public var showingPreviewPanel: Bool = false
    public var previewFileID: UUID?

    // MARK: - Drag & Drop

    public var isDropTargeted: Bool = false

    // MARK: - Error Handling

    public var currentError: VaultError?
    public var showError: Bool = false
    public var failedAttempts: Int = 0

    // MARK: - Init

    public init(engine: VaultEncryptionEngine = VaultEngine(), settings: AppSettings = AppSettings()) {
        self.engine = engine
        self.settings = settings
        loadPersistedVaults()
    }

    // MARK: - Computed Properties

    public var selectedVault: VaultInfo? {
        vaults.first { $0.id == selectedVaultID }
    }

    public var selectedVaultState: VaultState {
        guard let id = selectedVaultID else { return .locked }
        return vaultStates[id] ?? .locked
    }

    public var currentMetadata: VaultMetadata? {
        guard let id = selectedVaultID else { return nil }
        return vaultMetadata[id]
    }

    public var currentFiles: [VaultFileEntry] {
        guard let metadata = currentMetadata else { return [] }
        let filesInFolder = metadata.files.filter { $0.parentFolderID == currentFolderID }
        guard !searchText.isEmpty else { return filesInFolder }
        return filesInFolder.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    public var currentFolders: [VaultFileEntry] {
        currentFiles.filter(\.isFolder)
    }

    public var currentDocuments: [VaultFileEntry] {
        currentFiles.filter { !$0.isFolder }
    }

    public var totalFileSize: UInt64 {
        currentMetadata?.files.reduce(0) { $0 + $1.size } ?? 0
    }

    public var totalFileCount: Int {
        currentMetadata?.files.filter { !$0.isFolder }.count ?? 0
    }

    public var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalFileSize), countStyle: .file)
    }

    // MARK: - Vault Operations

    public func createVault(name: String, password: String, at path: URL, touchIDEnabled: Bool) async {
        do {
            let vault = try await engine.createVault(
                name: name,
                password: password,
                at: path,
                touchIDEnabled: touchIDEnabled
            )
            vaults.append(vault)
            settings.addKnownVault(vault)
            selectedVaultID = vault.id
            vaultStates[vault.id] = .locked
        } catch let error as VaultError {
            presentError(error)
        } catch {
            presentError(.encryptionFailed(error.localizedDescription))
        }
    }

    public func unlockVault(password: String) async {
        guard let vault = selectedVault else { return }
        let path = URL(fileURLWithPath: vault.containerPath)

        // Check rate limit before attempting unlock
        switch rateLimiter.checkAttempt(vaultPath: vault.containerPath) {
        case .delayed(let seconds):
            presentError(.rateLimited(seconds))
            return
        case .allowed:
            break
        }

        vaultStates[vault.id] = .unlocking
        do {
            let metadata = try await engine.unlockVault(at: path, password: password)
            vaultMetadata[vault.id] = metadata
            vaultStates[vault.id] = .unlocked
            failedAttempts = 0
            rateLimiter.recordSuccess(vaultPath: vault.containerPath)
            currentFolderID = nil
            navigationPath = []
            await configureAutoLock(interval: metadata.autoLockInterval)
        } catch VaultError.wrongPassword {
            failedAttempts += 1
            rateLimiter.recordFailure(vaultPath: vault.containerPath)
            vaultStates[vault.id] = .locked
            presentError(.wrongPassword)
        } catch let error as VaultError {
            vaultStates[vault.id] = .locked
            presentError(error)
        } catch {
            vaultStates[vault.id] = .locked
            presentError(.decryptionFailed(error.localizedDescription))
        }
    }

    public func unlockWithTouchID() async {
        guard let vault = selectedVault else { return }
        let path = URL(fileURLWithPath: vault.containerPath)

        vaultStates[vault.id] = .unlocking
        do {
            let metadata = try await engine.unlockVaultWithTouchID(at: path)
            vaultMetadata[vault.id] = metadata
            vaultStates[vault.id] = .unlocked
            failedAttempts = 0
            currentFolderID = nil
            navigationPath = []
            await configureAutoLock(interval: metadata.autoLockInterval)
        } catch let error as VaultError {
            vaultStates[vault.id] = .locked
            presentError(error)
        } catch {
            vaultStates[vault.id] = .locked
            presentError(.touchIDAuthFailed)
        }
    }

    public func lockVault() async {
        guard let vault = selectedVault else { return }
        let path = URL(fileURLWithPath: vault.containerPath)

        vaultStates[vault.id] = .locking
        do {
            try await engine.lockVault(at: path)
            vaultMetadata.removeValue(forKey: vault.id)
            vaultStates[vault.id] = .locked
            selectedFileIDs = []
            currentFolderID = nil
            navigationPath = []
            searchText = ""
        } catch {
            vaultStates[vault.id] = .unlocked
        }
    }

    public func lockAllVaults() async {
        for vault in vaults {
            guard vaultStates[vault.id] == .unlocked else { continue }
            let path = URL(fileURLWithPath: vault.containerPath)
            vaultStates[vault.id] = .locking
            try? await engine.lockVault(at: path)
            vaultMetadata.removeValue(forKey: vault.id)
            vaultStates[vault.id] = .locked
        }
        selectedFileIDs = []
        currentFolderID = nil
        navigationPath = []
        searchText = ""
    }

    // MARK: - File Operations

    public func addFiles(urls: [URL]) async {
        guard let vault = selectedVault else { return }
        let vaultPath = URL(fileURLWithPath: vault.containerPath)

        for url in urls {
            do {
                let entry = try await engine.addFile(
                    at: url,
                    to: vaultPath,
                    parentFolderID: currentFolderID,
                    secureDeleteOriginal: false
                )
                vaultMetadata[vault.id]?.files.append(entry)
            } catch let error as VaultError {
                presentError(error)
            } catch {
                presentError(.encryptionFailed(error.localizedDescription))
            }
        }
    }

    public func removeSelectedFiles() async {
        guard let vault = selectedVault else { return }
        let vaultPath = URL(fileURLWithPath: vault.containerPath)

        for fileID in selectedFileIDs {
            do {
                try await engine.removeFile(id: fileID, from: vaultPath)
                vaultMetadata[vault.id]?.files.removeAll { $0.id == fileID }
            } catch let error as VaultError {
                presentError(error)
            } catch {
                presentError(.decryptionFailed(error.localizedDescription))
            }
        }
        selectedFileIDs = []
    }

    @MainActor
    public func exportSelectedFiles() async {
        guard let vault = selectedVault else { return }
        let vaultPath = URL(fileURLWithPath: vault.containerPath)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"

        guard panel.runModal() == .OK, let destination = panel.url else { return }

        for fileID in selectedFileIDs {
            guard let file = currentMetadata?.files.first(where: { $0.id == fileID }) else { continue }
            let ext = file.originalExtension.isEmpty ? "" : ".\(file.originalExtension)"
            let destURL = destination.appendingPathComponent("\(file.name)\(ext)")
            do {
                try await engine.exportFile(id: fileID, from: vaultPath, to: destURL)
            } catch let error as VaultError {
                presentError(error)
            } catch {
                presentError(.decryptionFailed(error.localizedDescription))
            }
        }
    }

    public func createFolder(name: String) async {
        guard let vault = selectedVault else { return }
        let vaultPath = URL(fileURLWithPath: vault.containerPath)

        do {
            let folder = try await engine.createFolder(name: name, in: vaultPath, parentFolderID: currentFolderID)
            vaultMetadata[vault.id]?.files.append(folder)
        } catch let error as VaultError {
            presentError(error)
        } catch {
            presentError(.encryptionFailed(error.localizedDescription))
        }
    }

    public func previewFile(id: UUID) async -> Data? {
        guard let vault = selectedVault else { return nil }
        let vaultPath = URL(fileURLWithPath: vault.containerPath)
        return try? await engine.readFileToMemory(id: id, from: vaultPath)
    }

    // MARK: - Navigation

    public func navigateIntoFolder(_ folder: VaultFileEntry) {
        guard folder.isFolder else { return }
        navigationPath.append((id: folder.id, name: folder.name))
        currentFolderID = folder.id
        selectedFileIDs = []
    }

    public func navigateToRoot() {
        currentFolderID = nil
        navigationPath = []
        selectedFileIDs = []
    }

    public func navigateToBreadcrumb(index: Int) {
        guard index < navigationPath.count else { return }
        if index < 0 {
            navigateToRoot()
        } else {
            navigationPath = Array(navigationPath.prefix(index + 1))
            currentFolderID = navigationPath[index].id
            selectedFileIDs = []
        }
    }

    // MARK: - Vault Management

    public func deleteVault(id: UUID) {
        // Delete the container file from disk
        if let vault = vaults.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(atPath: vault.containerPath)
        }
        vaults.removeAll { $0.id == id }
        vaultStates.removeValue(forKey: id)
        vaultMetadata.removeValue(forKey: id)
        settings.removeKnownVault(id: id)
        if selectedVaultID == id {
            selectedVaultID = vaults.first?.id
        }
    }

    public func renameVault(id: UUID, newName: String) {
        guard let index = vaults.firstIndex(where: { $0.id == id }) else { return }
        let updated = VaultInfo(
            id: vaults[index].id,
            name: newName,
            containerPath: vaults[index].containerPath,
            createdDate: vaults[index].createdDate,
            touchIDEnabled: vaults[index].touchIDEnabled,
            isDecoy: vaults[index].isDecoy
        )
        vaults[index] = updated
        settings.addKnownVault(updated)
    }

    // MARK: - Auto-Lock

    @MainActor
    private func configureAutoLock(interval: AutoLockInterval) {
        if autoLockManager == nil {
            autoLockManager = AutoLockManager()
        }
        autoLockManager?.configure(interval: interval) { [weak self] in
            await self?.lockAllVaults()
        }
    }

    // MARK: - Error Handling

    private func presentError(_ error: VaultError) {
        currentError = error
        showError = true
    }

    // MARK: - Vault Persistence

    private func loadPersistedVaults() {
        let knownVaults = settings.knownVaults
        var validVaults: [VaultInfo] = []

        for vault in knownVaults {
            if FileManager.default.fileExists(atPath: vault.containerPath) {
                validVaults.append(vault)
                vaultStates[vault.id] = .locked
            }
        }

        // Prune stale entries
        if validVaults.count != knownVaults.count {
            settings.knownVaults = validVaults
        }

        vaults = validVaults
        selectedVaultID = vaults.first?.id
    }

    /// Scan the default vault directory for .vault files not yet tracked.
    public func discoverVaults() async {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return }
        let vaultDir = appSupport.appendingPathComponent("Vault")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: vaultDir,
            includingPropertiesForKeys: nil
        ) else { return }

        let knownPaths = Set(vaults.map(\.containerPath))

        for fileURL in contents where fileURL.pathExtension == "vault" {
            guard !knownPaths.contains(fileURL.path) else { continue }

            do {
                // Validate it's a real vault container by reading the header
                _ = try VaultContainer.readHeader(at: fileURL)
                let name = fileURL.deletingPathExtension().lastPathComponent
                let vault = VaultInfo(
                    id: UUID(),
                    name: name,
                    containerPath: fileURL.path,
                    createdDate: Date(),
                    touchIDEnabled: false,
                    isDecoy: false
                )
                vaults.append(vault)
                vaultStates[vault.id] = .locked
                settings.addKnownVault(vault)
            } catch {
                continue
            }
        }

        if selectedVaultID == nil {
            selectedVaultID = vaults.first?.id
        }
    }
}

// MARK: - File Helpers

public extension VaultFileEntry {
    var displayName: String {
        if isFolder { return name }
        return originalExtension.isEmpty ? name : "\(name).\(originalExtension)"
    }

    var iconName: String {
        if isFolder { return "folder.fill" }
        switch originalExtension.lowercased() {
        case "pdf": return "doc.fill"
        case "jpg", "jpeg", "png", "heic", "gif", "webp": return "photo.fill"
        case "mp4", "mov", "avi", "mkv": return "film.fill"
        case "mp3", "wav", "aac", "flac": return "music.note"
        case "txt", "md", "rtf": return "doc.text.fill"
        case "zip", "gz", "tar", "7z": return "doc.zipper"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "doc", "docx": return "doc.richtext.fill"
        case "key", "pem", "dat": return "key.fill"
        default: return "doc.fill"
        }
    }

    var iconColor: Color {
        if isFolder { return .blue }
        switch originalExtension.lowercased() {
        case "pdf": return .red
        case "jpg", "jpeg", "png", "heic", "gif", "webp": return .green
        case "mp4", "mov", "avi", "mkv": return .purple
        case "mp3", "wav", "aac", "flac": return .pink
        case "key", "pem", "dat": return .orange
        default: return .gray
        }
    }

    var formattedSize: String {
        if isFolder { return "--" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modifiedDate)
    }
}
