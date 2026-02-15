// SecureMemory.swift
// Vault
//
// Secure memory utilities: zero-on-deinit data wrapper and mlock/munlock for swap prevention.

import Foundation
import Darwin

// MARK: - ManagedData

/// A wrapper around mutable bytes that guarantees memory is zeroed on deallocation.
/// Use this for any sensitive data (encryption keys, plaintext passwords) that must
/// not linger in memory after use.
public final class ManagedData {
    private let pointer: UnsafeMutableRawPointer
    public private(set) var count: Int
    private var isLocked: Bool = false

    /// Initialize with a copy of existing data. The original data is NOT zeroed — caller
    /// is responsible for clearing it if needed.
    public init(data: Data) {
        self.count = data.count
        self.pointer = UnsafeMutableRawPointer.allocate(byteCount: max(count, 1), alignment: 1)
        data.withUnsafeBytes { buffer in
            if let base = buffer.baseAddress {
                pointer.copyMemory(from: base, byteCount: count)
            }
        }
    }

    /// Initialize by allocating a zeroed buffer of the given size.
    public init(count: Int) {
        self.count = count
        self.pointer = UnsafeMutableRawPointer.allocate(byteCount: max(count, 1), alignment: 1)
        memset(pointer, 0, count)
    }

    deinit {
        zeroMemory()
        unlockMemory()
        pointer.deallocate()
    }

    // MARK: - Access

    /// Execute a closure with read-only access to the underlying bytes.
    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try body(UnsafeRawBufferPointer(start: pointer, count: count))
    }

    /// Execute a closure with mutable access to the underlying bytes.
    public func withUnsafeMutableBytes<R>(_ body: (UnsafeMutableRawBufferPointer) throws -> R) rethrows -> R {
        try body(UnsafeMutableRawBufferPointer(start: pointer, count: count))
    }

    /// Export the contents as Data. Use sparingly — the returned Data is a normal
    /// heap allocation that Swift's ARC manages; it will NOT be zeroed automatically.
    public func toData() -> Data {
        Data(bytes: pointer, count: count)
    }

    // MARK: - Memory Locking

    /// Lock the memory region so the OS will not swap it to disk.
    @discardableResult
    public func lockMemory() -> Bool {
        guard !isLocked else { return true }
        let result = Darwin.mlock(pointer, count)
        if result == 0 {
            isLocked = true
        }
        return result == 0
    }

    /// Unlock the memory region, allowing the OS to swap it if needed.
    @discardableResult
    public func unlockMemory() -> Bool {
        guard isLocked else { return true }
        let result = Darwin.munlock(pointer, count)
        if result == 0 {
            isLocked = false
        }
        return result == 0
    }

    // MARK: - Zeroing

    /// Overwrite the buffer with zeros. Uses volatile-equivalent pattern to prevent
    /// the compiler from optimizing the write away.
    public func zeroMemory() {
        // memset_s is guaranteed not to be optimized away (C11 Annex K).
        // Darwin provides it.
        memset_s(pointer, count, 0, count)
    }
}

// MARK: - Data Extension

extension Data {
    /// Zero the bytes of this Data in place. Only works when this Data instance
    /// has sole ownership of its backing store (i.e., no other references via COW).
    public mutating func zeroOut() {
        guard !isEmpty else { return }
        withUnsafeMutableBytes { buffer in
            if let base = buffer.baseAddress {
                memset_s(base, buffer.count, 0, buffer.count)
            }
        }
    }
}
