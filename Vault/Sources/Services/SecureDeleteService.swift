// SecureDeleteService.swift
// Vault
//
// 3-pass secure file deletion: random → zeros → random → unlink.

import Foundation

/// Securely deletes files by overwriting contents before removal.
/// Uses a 3-pass scheme: random data, zeros, random data, then file removal.
public enum SecureDeleteService {

    // MARK: - Configuration

    private static let passCount = 3
    private static let bufferSize = 64 * 1024 // 64 KB write buffer

    // MARK: - Public API

    /// Securely delete a file at the given URL.
    /// Overwrites contents with 3 passes then removes the file.
    /// - Parameter url: The file URL to securely delete.
    /// - Throws: `VaultError.secureDeleteFailed` if any step fails.
    public static func secureDelete(at url: URL) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw VaultError.secureDeleteFailed("File not found: \(url.lastPathComponent)")
        }

        if isDirectory.boolValue {
            try secureDeleteDirectory(at: url)
        } else {
            try secureDeleteFile(at: url)
        }
    }

    // MARK: - File Deletion

    private static func secureDeleteFile(at url: URL) throws {
        let path = url.path

        // Get file size
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let fileSize = attrs[.size] as? UInt64 else {
            throw VaultError.secureDeleteFailed("Cannot read file attributes: \(url.lastPathComponent)")
        }

        guard fileSize > 0 else {
            // Empty file — just delete it
            try removeFile(at: url)
            return
        }

        // Open file for writing
        guard let handle = FileHandle(forWritingAtPath: path) else {
            throw VaultError.secureDeleteFailed("Cannot open file for overwrite: \(url.lastPathComponent)")
        }

        defer { handle.closeFile() }

        // Pass 1: Random data
        try overwritePass(handle: handle, fileSize: fileSize, pattern: .random)
        // Pass 2: Zeros
        try overwritePass(handle: handle, fileSize: fileSize, pattern: .zeros)
        // Pass 3: Random data
        try overwritePass(handle: handle, fileSize: fileSize, pattern: .random)

        // Truncate to zero length before deletion
        handle.truncateFile(atOffset: 0)
        handle.closeFile()

        // Remove the file
        try removeFile(at: url)

        // Verify deletion
        if FileManager.default.fileExists(atPath: path) {
            throw VaultError.secureDeleteFailed("File still exists after deletion: \(url.lastPathComponent)")
        }
    }

    // MARK: - Directory Deletion

    private static func secureDeleteDirectory(at url: URL) throws {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw VaultError.secureDeleteFailed("Cannot enumerate directory: \(url.lastPathComponent)")
        }

        // Collect all files first (enumerate before modifying)
        var files: [URL] = []
        var subdirectories: [URL] = []

        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues.isDirectory == true {
                subdirectories.append(fileURL)
            } else {
                files.append(fileURL)
            }
        }

        // Delete all files first
        for fileURL in files {
            try secureDeleteFile(at: fileURL)
        }

        // Remove directories deepest-first
        for dirURL in subdirectories.reversed() {
            try fileManager.removeItem(at: dirURL)
        }

        // Remove the root directory
        try fileManager.removeItem(at: url)
    }

    // MARK: - Overwrite Engine

    private enum OverwritePattern {
        case random
        case zeros
    }

    private static func overwritePass(
        handle: FileHandle,
        fileSize: UInt64,
        pattern: OverwritePattern
    ) throws {
        handle.seek(toFileOffset: 0)

        var remaining = fileSize
        while remaining > 0 {
            let chunkSize = Int(min(remaining, UInt64(bufferSize)))
            let data: Data

            switch pattern {
            case .random:
                data = randomData(count: chunkSize)
            case .zeros:
                data = Data(count: chunkSize)
            }

            handle.write(data)
            remaining -= UInt64(chunkSize)
        }

        // Force flush to disk
        handle.synchronizeFile()
    }

    private static func randomData(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let result = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        if result != errSecSuccess {
            // Fallback: arc4random-based fill
            for i in 0..<count {
                bytes[i] = UInt8.random(in: 0...255)
            }
        }
        return Data(bytes)
    }

    private static func removeFile(at url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw VaultError.secureDeleteFailed("Failed to remove file: \(error.localizedDescription)")
        }
    }
}
