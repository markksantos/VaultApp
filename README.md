<div align="center">

# 🔐 VaultApp

**Encrypted file vault for macOS with AES-256, Touch ID, and Finder integration**

[![Swift](https://img.shields.io/badge/Swift-F05138?style=for-the-badge&logo=swift&logoColor=white)](#)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-007AFF?style=for-the-badge&logo=apple&logoColor=white)](#)
[![macOS](https://img.shields.io/badge/macOS_14+-000000?style=for-the-badge&logo=apple&logoColor=white)](#)

[Features](#-features) · [Getting Started](#-getting-started) · [Tech Stack](#️-tech-stack)

</div>

---

## ✨ Features

- **AES-256-GCM Encryption** — Industry-standard authenticated encryption for all vault contents
- **Touch ID Unlock** — Biometric authentication via Keychain integration
- **Panic Lock** — Global hotkey (⌘⇧L) for instant emergency vault locking
- **Decoy Vaults** — Plausible deniability with a second password that opens different files
- **Secure Delete** — 3-pass overwrite (random → zeros → random) before file removal
- **Auto-Lock** — Configurable triggers: timed intervals, screen lock, or system sleep
- **Finder Integration** — Right-click "Add to Vault" context menu via FinderSync extension
- **Drag-and-Drop** — Add files by dragging into the vault window
- **Rate Limiting** — Escalating lockout delays after failed password attempts
- **Folder Organization** — Hierarchical folder structure within vaults with search and preview

## 🚀 Getting Started

### Prerequisites

- macOS 14.0+
- Xcode 15+
- Swift 5.9+

### Installation

```bash
git clone https://github.com/markksantos/VaultApp.git
cd VaultApp
swift build
open Package.swift
```

### Running Tests

```bash
swift test
```

## 🛠️ Tech Stack

| Category | Technology |
|----------|-----------|
| Language | Swift 5.9 |
| UI | SwiftUI + AppKit |
| Encryption | CryptoKit (AES-256-GCM) |
| Key Derivation | CommonCrypto (PBKDF2-HMAC-SHA256, 600K iterations) |
| Biometrics | LocalAuthentication (Touch ID) |
| Keychain | Security framework |
| Architecture | MVVM with @Observable |
| Build | Swift Package Manager |

## 📁 Project Structure

```
Vault/Sources/
├── App/
│   └── VaultApp.swift                 # Entry point & AppDelegate
├── Models/
│   └── VaultModels.swift              # Core data models & protocols
├── Encryption/
│   ├── VaultEngine.swift              # Main encryption engine
│   ├── VaultContainer.swift           # Custom binary container format
│   ├── AESEncryptor.swift             # AES-256-GCM implementation
│   ├── KeyDerivation.swift            # PBKDF2 key derivation
│   ├── KeychainManager.swift          # Keychain + Touch ID
│   └── SecureMemory.swift             # Memory locking & zeroing
├── Security/
│   ├── PanicLockManager.swift         # Global hotkey emergency lock
│   ├── AutoLockManager.swift          # Timed/event auto-lock
│   ├── DecoyVaultManager.swift        # Plausible deniability
│   └── RateLimiter.swift              # Brute-force protection
├── Services/
│   ├── SecureDeleteService.swift      # 3-pass secure file wipe
│   └── TempFileManager.swift          # Temp file cleanup
└── UI/
    ├── Views/
    │   ├── LockScreenView.swift       # Password/Touch ID unlock
    │   ├── UnlockedVaultView.swift     # File grid/list browser
    │   └── VaultCreationWizard.swift   # Multi-step vault setup
    └── ViewModels/
        └── VaultViewModel.swift        # Main view model
```

## 📄 License

MIT License © 2025 Mark Santos
