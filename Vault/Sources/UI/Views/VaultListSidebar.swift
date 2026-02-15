// VaultListSidebar.swift
// Vault
//
// Sidebar showing all vaults with create button, context menus, and state indicators.

import SwiftUI

public struct VaultListSidebar: View {
    @Bindable public var viewModel: VaultViewModel

    @State private var renamingVaultID: UUID?
    @State private var renameText: String = ""
    @State private var showDeleteConfirmation: Bool = false
    @State private var vaultToDelete: UUID?

    public init(viewModel: VaultViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Vaults")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(viewModel.vaults.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background {
                        Capsule().fill(.quaternary)
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Vault List
            List(viewModel.vaults, selection: $viewModel.selectedVaultID) { vault in
                vaultRow(vault)
                    .tag(vault.id)
                    .contextMenu { contextMenu(for: vault) }
            }
            .listStyle(.sidebar)

            Divider()

            // Create Button
            Button {
                viewModel.showingCreationWizard = true
            } label: {
                Label("New Vault", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .alert("Delete Vault?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let id = vaultToDelete {
                    viewModel.deleteVault(id: id)
                }
            }
        } message: {
            Text("This will permanently remove the vault and all its encrypted contents. This cannot be undone.")
        }
    }

    // MARK: - Vault Row

    @ViewBuilder
    private func vaultRow(_ vault: VaultInfo) -> some View {
        HStack(spacing: 10) {
            // Lock state icon
            Image(systemName: stateIcon(for: vault.id))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(stateColor(for: vault.id))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                if renamingVaultID == vault.id {
                    TextField("Vault name", text: $renameText, onCommit: {
                        viewModel.renameVault(id: vault.id, newName: renameText)
                        renamingVaultID = nil
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                } else {
                    Text(vault.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text(stateLabel(for: vault.id))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if vault.touchIDEnabled {
                        Image(systemName: "touchid")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenu(for vault: VaultInfo) -> some View {
        Button {
            renameText = vault.name
            renamingVaultID = vault.id
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button {
            NSWorkspace.shared.selectFile(
                vault.containerPath,
                inFileViewerRootedAtPath: URL(fileURLWithPath: vault.containerPath).deletingLastPathComponent().path
            )
        } label: {
            Label("Show in Finder", systemImage: "folder")
        }

        Divider()

        Button(role: .destructive) {
            vaultToDelete = vault.id
            showDeleteConfirmation = true
        } label: {
            Label("Delete Vault", systemImage: "trash")
        }
    }

    // MARK: - State Helpers

    private func stateIcon(for vaultID: UUID) -> String {
        switch viewModel.vaultStates[vaultID] ?? .locked {
        case .locked: return "lock.fill"
        case .unlocking, .locking: return "lock.rotation"
        case .unlocked: return "lock.open.fill"
        }
    }

    private func stateColor(for vaultID: UUID) -> Color {
        switch viewModel.vaultStates[vaultID] ?? .locked {
        case .locked: return .red
        case .unlocking, .locking: return .orange
        case .unlocked: return .green
        }
    }

    private func stateLabel(for vaultID: UUID) -> String {
        switch viewModel.vaultStates[vaultID] ?? .locked {
        case .locked: return "Locked"
        case .unlocking: return "Unlocking..."
        case .locking: return "Locking..."
        case .unlocked: return "Unlocked"
        }
    }
}

#Preview {
    VaultListSidebar(viewModel: VaultViewModel(engine: MockVaultEngine()))
        .frame(width: 240, height: 500)
}
