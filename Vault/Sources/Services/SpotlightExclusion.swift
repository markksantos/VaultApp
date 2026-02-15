// SpotlightExclusion.swift
// Vault
//
// Exclude vault containers from Spotlight indexing and Time Machine backups.

import Foundation

/// Utilities for excluding vault directories from system indexing and backups.
public enum SpotlightExclusion {

    // MARK: - Public API

    /// Apply all exclusions to a vault container directory.
    /// Creates .noindex marker file and sets extended attributes to exclude
    /// from Spotlight and Time Machine.
    /// - Parameter directoryURL: The vault container's parent directory.
    public static func applyExclusions(to directoryURL: URL) throws {
        try createNoIndexFile(in: directoryURL)
        try setSpotlightExclusionAttribute(at: directoryURL)
        try setTimeMachineExclusion(at: directoryURL)
    }

    /// Remove exclusions from a vault container directory.
    /// - Parameter directoryURL: The vault container's parent directory.
    public static func removeExclusions(from directoryURL: URL) throws {
        try removeNoIndexFile(from: directoryURL)
        try removeTimeMachineExclusion(at: directoryURL)
    }

    // MARK: - .noindex File

    /// Create a .noindex file that tells Spotlight to skip this directory.
    private static func createNoIndexFile(in directoryURL: URL) throws {
        let noIndexURL = directoryURL.appendingPathComponent(".noindex")
        if !FileManager.default.fileExists(atPath: noIndexURL.path) {
            FileManager.default.createFile(atPath: noIndexURL.path, contents: nil)
        }
    }

    private static func removeNoIndexFile(from directoryURL: URL) throws {
        let noIndexURL = directoryURL.appendingPathComponent(".noindex")
        if FileManager.default.fileExists(atPath: noIndexURL.path) {
            try FileManager.default.removeItem(at: noIndexURL)
        }
    }

    // MARK: - Spotlight Extended Attribute

    /// Set the Spotlight exclusion extended attribute on the directory.
    private static func setSpotlightExclusionAttribute(at url: URL) throws {
        let attributeName = "com.apple.metadata:com_apple_backup_excludeItem"
        let value = "com.apple.backupd" as NSString
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: value,
            requiringSecureCoding: false
        ) else {
            return
        }

        let result = url.path.withCString { path in
            data.withUnsafeBytes { buffer -> Int32 in
                guard let baseAddress = buffer.baseAddress else { return -1 }
                return attributeName.withCString { name in
                    setxattr(path, name, baseAddress, buffer.count, 0, XATTR_NOFOLLOW)
                }
            }
        }

        if result != 0 {
            // Non-fatal: log but don't throw. Spotlight exclusion is best-effort.
        }
    }

    // MARK: - Time Machine Exclusion

    /// Exclude the directory from Time Machine backups using the resource value API.
    private static func setTimeMachineExclusion(at url: URL) throws {
        var mutableURL = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try mutableURL.setResourceValues(resourceValues)
    }

    private static func removeTimeMachineExclusion(at url: URL) throws {
        var mutableURL = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = false
        try mutableURL.setResourceValues(resourceValues)
    }
}
