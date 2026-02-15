// DragDropHandler.swift
// Vault
//
// NSView-based drop delegate and drag-drop utilities for file import/export.

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drop Delegate View Modifier

public struct VaultDropDelegate: DropDelegate {
    public let onDrop: ([URL]) -> Void
    @Binding public var isTargeted: Bool

    public init(onDrop: @escaping ([URL]) -> Void, isTargeted: Binding<Bool>) {
        self.onDrop = onDrop
        self._isTargeted = isTargeted
    }

    public func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    public func dropEntered(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.2)) {
            isTargeted = true
        }
    }

    public func dropExited(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.2)) {
            isTargeted = false
        }
    }

    public func performDrop(info: DropInfo) -> Bool {
        withAnimation(.easeInOut(duration: 0.2)) {
            isTargeted = false
        }

        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }

        var collectedURLs: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                defer { group.leave() }
                guard let urlData = data as? Data,
                      let path = String(data: urlData, encoding: .utf8),
                      let url = URL(string: path) else { return }
                collectedURLs.append(url)
            }
        }

        group.notify(queue: .main) {
            if !collectedURLs.isEmpty {
                onDrop(collectedURLs)
            }
        }

        return true
    }
}

// MARK: - Drop Zone Overlay

public struct DropZoneOverlay: View {
    public let isTargeted: Bool

    public init(isTargeted: Bool) {
        self.isTargeted = isTargeted
    }

    public var body: some View {
        ZStack {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                    )
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor.opacity(0.08))
                    }
                    .transition(.opacity)

                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.accentColor)
                    Text("Drop to Encrypt")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isTargeted)
        .allowsHitTesting(false)
    }
}

// MARK: - View Extension

public extension View {
    func vaultDropZone(isTargeted: Binding<Bool>, onDrop: @escaping ([URL]) -> Void) -> some View {
        self
            .onDrop(of: [.fileURL], delegate: VaultDropDelegate(onDrop: onDrop, isTargeted: isTargeted))
            .overlay { DropZoneOverlay(isTargeted: isTargeted.wrappedValue) }
    }
}
