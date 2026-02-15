// swift-tools-version: 5.9
// Package.swift
// Vault — macOS encrypted file vault application.

import PackageDescription

let package = Package(
    name: "Vault",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Vault", targets: ["Vault"]),
    ],
    targets: [
        .target(
            name: "VaultCore",
            path: "Vault/Sources",
            exclude: ["App"],
            sources: [
                "Models",
                "Encryption",
                "Security",
                "Services",
                "UI",
            ]
        ),
        .executableTarget(
            name: "Vault",
            dependencies: ["VaultCore"],
            path: "Vault/Sources/App"
        ),
        .testTarget(
            name: "VaultTests",
            dependencies: ["VaultCore"],
            path: "Tests/VaultTests"
        ),
    ]
)
