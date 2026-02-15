// VaultModels.swift
// Vault
//
// Shared data models used across the encryption engine, UI, and security layers.

import Foundation

// MARK: - Vault Container Format

/// Magic bytes identifying a Vault container file
public let kVaultMagicBytes: [UInt8] = [0x56, 0x4C, 0x54, 0x58] // "VLTX"
public let kVaultFormatVersion: UInt16 = 1

/// On-disk vault container header (unencrypted portion)
public struct VaultContainerHeader {
    public let magic: [UInt8]          // 4 bytes: "VLTX"
    public let version: UInt16         // 2 bytes: format version
    public let salt: Data              // 32 bytes: key derivation salt
    public let metadataNonce: Data     // 12 bytes: nonce for encrypted metadata block
    public let metadataLength: UInt64  // 8 bytes: length of encrypted metadata
    public let kdfAlgorithm: KDFAlgorithm // 1 byte: which KDF was used
    public let kdfIterations: UInt32   // 4 bytes: iteration count (for PBKDF2)
    public let kdfMemory: UInt32       // 4 bytes: memory parameter (for Argon2)

    public static let fixedSize: Int = 4 + 2 + 32 + 12 + 8 + 1 + 4 + 4 // 67 bytes

    public init(magic: [UInt8], version: UInt16, salt: Data, metadataNonce: Data, metadataLength: UInt64, kdfAlgorithm: KDFAlgorithm, kdfIterations: UInt32, kdfMemory: UInt32) {
        self.magic = magic
        self.version = version
        self.salt = salt
        self.metadataNonce = metadataNonce
        self.metadataLength = metadataLength
        self.kdfAlgorithm = kdfAlgorithm
        self.kdfIterations = kdfIterations
        self.kdfMemory = kdfMemory
    }
}

public enum KDFAlgorithm: UInt8, Codable {
    case pbkdf2HMACSHA256 = 0x01
    case argon2id = 0x02
}

// MARK: - Vault Metadata (encrypted inside container)

/// Represents a file entry in the vault's encrypted metadata index
public struct VaultFileEntry: Codable, Identifiable {
    public let id: UUID
    public var name: String
    public var originalExtension: String
    public var size: UInt64
    public var offset: UInt64          // byte offset within container's data section
    public var nonce: Data             // 12 bytes: individual file encryption nonce
    public var parentFolderID: UUID?   // nil = root level
    public var createdDate: Date
    public var modifiedDate: Date
    public var isFolder: Bool
    public var mimeType: String?
    public var thumbnailData: Data?    // small preview thumbnail, encrypted with file

    public init(id: UUID, name: String, originalExtension: String, size: UInt64, offset: UInt64, nonce: Data, parentFolderID: UUID?, createdDate: Date, modifiedDate: Date, isFolder: Bool, mimeType: String?, thumbnailData: Data?) {
        self.id = id
        self.name = name
        self.originalExtension = originalExtension
        self.size = size
        self.offset = offset
        self.nonce = nonce
        self.parentFolderID = parentFolderID
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.isFolder = isFolder
        self.mimeType = mimeType
        self.thumbnailData = thumbnailData
    }
}

/// Encrypted metadata block stored in the container
public struct VaultMetadata: Codable {
    public var vaultName: String
    public var createdDate: Date
    public var lastModifiedDate: Date
    public var files: [VaultFileEntry]
    public var touchIDEnabled: Bool
    public var autoLockInterval: AutoLockInterval
    public var hasDecoyVault: Bool
    public var decoyFiles: [VaultFileEntry]?  // populated only if decoy vault enabled
    public var failedAttemptCount: Int
    public var lastFailedAttemptDate: Date?
    public var wipeAfterMaxAttempts: Bool
    public var maxFailedAttempts: Int

    public init(vaultName: String, createdDate: Date, lastModifiedDate: Date, files: [VaultFileEntry], touchIDEnabled: Bool, autoLockInterval: AutoLockInterval, hasDecoyVault: Bool, decoyFiles: [VaultFileEntry]?, failedAttemptCount: Int, lastFailedAttemptDate: Date?, wipeAfterMaxAttempts: Bool, maxFailedAttempts: Int) {
        self.vaultName = vaultName
        self.createdDate = createdDate
        self.lastModifiedDate = lastModifiedDate
        self.files = files
        self.touchIDEnabled = touchIDEnabled
        self.autoLockInterval = autoLockInterval
        self.hasDecoyVault = hasDecoyVault
        self.decoyFiles = decoyFiles
        self.failedAttemptCount = failedAttemptCount
        self.lastFailedAttemptDate = lastFailedAttemptDate
        self.wipeAfterMaxAttempts = wipeAfterMaxAttempts
        self.maxFailedAttempts = maxFailedAttempts
    }
}

// MARK: - Auto-lock Configuration

public enum AutoLockInterval: String, Codable, CaseIterable {
    case oneMinute = "1min"
    case fiveMinutes = "5min"
    case fifteenMinutes = "15min"
    case thirtyMinutes = "30min"
    case onScreenLock = "screenLock"
    case onSleep = "sleep"
    case never = "never"

    public var displayName: String {
        switch self {
        case .oneMinute: return "1 Minute"
        case .fiveMinutes: return "5 Minutes"
        case .fifteenMinutes: return "15 Minutes"
        case .thirtyMinutes: return "30 Minutes"
        case .onScreenLock: return "On Screen Lock"
        case .onSleep: return "On Sleep"
        case .never: return "Never"
        }
    }

    public var timeInterval: TimeInterval? {
        switch self {
        case .oneMinute: return 60
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        case .thirtyMinutes: return 1800
        case .onScreenLock, .onSleep, .never: return nil
        }
    }
}

// MARK: - Vault State

public enum VaultState: Equatable {
    case locked
    case unlocking
    case unlocked
    case locking
}

// MARK: - Vault Info (for sidebar / vault list)

public struct VaultInfo: Identifiable, Codable {
    public let id: UUID
    public var name: String
    public var containerPath: String   // path to the .vault container file
    public var createdDate: Date
    public var touchIDEnabled: Bool
    public var isDecoy: Bool

    public init(id: UUID, name: String, containerPath: String, createdDate: Date, touchIDEnabled: Bool, isDecoy: Bool) {
        self.id = id
        self.name = name
        self.containerPath = containerPath
        self.createdDate = createdDate
        self.touchIDEnabled = touchIDEnabled
        self.isDecoy = isDecoy
    }
}

// MARK: - Licensing

public enum LicenseTier {
    case free   // 1 vault, 10 files max
    case paid   // unlimited

    public var maxVaults: Int {
        switch self {
        case .free: return 1
        case .paid: return Int.max
        }
    }

    public var maxFilesPerVault: Int {
        switch self {
        case .free: return 10
        case .paid: return Int.max
        }
    }
}

// MARK: - Errors

public enum VaultError: LocalizedError {
    case invalidContainer
    case corruptedMetadata
    case wrongPassword
    case containerNotFound
    case fileNotFound(String)
    case encryptionFailed(String)
    case decryptionFailed(String)
    case keyDerivationFailed
    case touchIDNotAvailable
    case touchIDAuthFailed
    case vaultLimitReached
    case fileLimitReached
    case fileAlreadyExists(String)
    case containerWriteFailed(String)
    case secureDeleteFailed(String)
    case rateLimited(TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .invalidContainer: return "Not a valid Vault container file."
        case .corruptedMetadata: return "Vault metadata is corrupted."
        case .wrongPassword: return "Incorrect password."
        case .containerNotFound: return "Vault container file not found."
        case .fileNotFound(let name): return "File '\(name)' not found in vault."
        case .encryptionFailed(let detail): return "Encryption failed: \(detail)"
        case .decryptionFailed(let detail): return "Decryption failed: \(detail)"
        case .keyDerivationFailed: return "Failed to derive encryption key."
        case .touchIDNotAvailable: return "Touch ID is not available on this device."
        case .touchIDAuthFailed: return "Touch ID authentication failed."
        case .vaultLimitReached: return "Free tier: maximum 1 vault. Upgrade to unlock unlimited vaults."
        case .fileLimitReached: return "Free tier: maximum 10 files per vault. Upgrade for unlimited."
        case .fileAlreadyExists(let name): return "File '\(name)' already exists in vault."
        case .containerWriteFailed(let detail): return "Failed to write container: \(detail)"
        case .secureDeleteFailed(let detail): return "Secure delete failed: \(detail)"
        case .rateLimited(let wait): return "Too many failed attempts. Wait \(Int(wait)) seconds."
        }
    }
}

// MARK: - Protocols

/// Protocol for the encryption engine — used by UI and services to interact with vaults
public protocol VaultEncryptionEngine {
    /// Create a new vault container at the specified path
    func createVault(name: String, password: String, at path: URL, touchIDEnabled: Bool) async throws -> VaultInfo

    /// Unlock a vault and return its metadata
    func unlockVault(at path: URL, password: String) async throws -> VaultMetadata

    /// Unlock a vault using Touch ID (retrieves key from Keychain)
    func unlockVaultWithTouchID(at path: URL) async throws -> VaultMetadata

    /// Lock a vault — clears decrypted key material from memory
    func lockVault(at path: URL) async throws

    /// Add a file to an unlocked vault
    func addFile(at sourceURL: URL, to vaultPath: URL, parentFolderID: UUID?, secureDeleteOriginal: Bool) async throws -> VaultFileEntry

    /// Remove a file from the vault
    func removeFile(id: UUID, from vaultPath: URL) async throws

    /// Read/decrypt a file from the vault to a temporary location
    func readFile(id: UUID, from vaultPath: URL) async throws -> URL

    /// Read/decrypt a file from the vault into memory (for preview)
    func readFileToMemory(id: UUID, from vaultPath: URL) async throws -> Data

    /// Export (decrypt) a file to a chosen destination
    func exportFile(id: UUID, from vaultPath: URL, to destinationURL: URL) async throws

    /// Create a folder within the vault
    func createFolder(name: String, in vaultPath: URL, parentFolderID: UUID?) async throws -> VaultFileEntry

    /// Get current metadata for an unlocked vault
    func getMetadata(for vaultPath: URL) async throws -> VaultMetadata

    /// Update vault metadata (e.g., settings changes)
    func updateMetadata(_ metadata: VaultMetadata, for vaultPath: URL) async throws
}
