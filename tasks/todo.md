# Vault App - Build Plan

## Architecture
- Stack: Swift + SwiftUI, CryptoKit, LocalAuthentication, AppKit, FileManager
- Target: macOS 13+
- 3 parallel workstreams: Encryption Engine, Main UI, Finder + Security

## Workstream 1: Encryption Engine
- [x] CryptoKit AES-256-GCM encryption/decryption
- [x] Key derivation (PBKDF2-HMAC-SHA256 600k+ iterations, Argon2id preferred)
- [x] Vault container format (header, encrypted metadata, file blocks)
- [x] File add/remove/read operations on encrypted store
- [x] Keychain integration for Touch ID key storage
- [x] Container compaction after file removal
- [x] Secure memory handling (mlock, zeroing on dealloc)

## Workstream 2: Main App UI
- [x] Lock screen (password field, Touch ID button, dark/minimal design)
- [x] Vault creation wizard (multi-step)
- [x] Unlocked view with grid/list toggle
- [x] Drag-and-drop (in and out)
- [x] File preview via Quick Look
- [x] Search within unlocked vault
- [x] Multiple vaults sidebar
- [x] App entry point and navigation
- [x] Password strength indicator
- [x] Mock vault engine for standalone UI testing

## Workstream 3: Finder Integration + Security
- [x] FinderSync extension for right-click "Add to Vault"
- [x] Auto-lock timer with configurable intervals
- [x] Panic shortcut (global hotkey locks all vaults)
- [x] Memory protection (zeroing sensitive data)
- [x] Secure delete of originals (3-pass overwrite)
- [x] Spotlight exclusion
- [x] Failed attempt rate limiting
- [x] Decoy vault support
- [x] Temp file cleanup manager
- [x] App settings (UserDefaults-backed)
- [x] Package.swift + entitlements

## Status: INITIAL BUILD COMPLETE

## Next Steps
- [ ] Xcode project setup (or convert SPM to Xcode project)
- [ ] Build verification — resolve any compilation issues
- [ ] Wire mock engine to real VaultEngine in app entry point
- [ ] Add unit tests for encryption engine
- [ ] Integration testing (end-to-end vault create/add/lock/unlock)
- [ ] App icon and visual polish
- [ ] Notarization and sandboxing
- [ ] In-app purchase for $14.99 paid tier
