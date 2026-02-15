// UnlockedVaultView.swift
// Vault
//
// File browser with grid/list toggle, toolbar, breadcrumbs, drag-drop zone, and empty state.

import SwiftUI
import AppKit

public struct UnlockedVaultView: View {
    @Bindable public var viewModel: VaultViewModel

    @State private var isDropTargeted: Bool = false
    @State private var showNewFolderAlert: Bool = false
    @State private var newFolderName: String = ""
    @State private var showDeleteConfirmation: Bool = false

    public init(viewModel: VaultViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            Divider()

            // Breadcrumbs
            breadcrumbs
                .padding(.horizontal, 16)
                .padding(.vertical, 6)

            Divider()

            // File content area
            if viewModel.currentFiles.isEmpty && viewModel.searchText.isEmpty {
                emptyState
            } else if viewModel.currentFiles.isEmpty {
                noSearchResults
            } else if viewModel.isGridView {
                gridView
            } else {
                listView
            }

            Divider()

            // Status bar
            statusBar
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        }
        .vaultDropZone(isTargeted: $isDropTargeted) { urls in
            Task { await viewModel.addFiles(urls: urls) }
        }
        .alert("New Folder", isPresented: $showNewFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Create") {
                Task { await viewModel.createFolder(name: newFolderName) }
                newFolderName = ""
            }
        } message: {
            Text("Enter a name for the new folder.")
        }
        .alert("Delete Selected?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await viewModel.removeSelectedFiles() }
            }
        } message: {
            Text("The selected items will be permanently removed from this vault.")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            // Search
            SearchBar(text: $viewModel.searchText)
                .frame(maxWidth: 220)

            Spacer()

            // Add files
            Button {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = true
                panel.canChooseFiles = true
                panel.canChooseDirectories = true
                if panel.runModal() == .OK {
                    Task { await viewModel.addFiles(urls: panel.urls) }
                }
            } label: {
                Label("Add Files", systemImage: "plus")
            }
            .help("Add files to vault")

            // New folder
            Button {
                showNewFolderAlert = true
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            .help("Create new folder")

            // Delete
            Button {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(viewModel.selectedFileIDs.isEmpty)
            .help("Delete selected items")

            // Export
            Button {
                Task { await viewModel.exportSelectedFiles() }
            } label: {
                Label("Export", systemImage: "arrow.up.doc")
            }
            .disabled(viewModel.selectedFileIDs.isEmpty)
            .help("Export selected items")

            Divider()
                .frame(height: 16)

            // View toggle
            Picker("View", selection: $viewModel.isGridView) {
                Image(systemName: "square.grid.2x2")
                    .tag(true)
                Image(systemName: "list.bullet")
                    .tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 70)

            Divider()
                .frame(height: 16)

            // Lock button
            Button {
                Task { await viewModel.lockVault() }
            } label: {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.orange)
            }
            .help("Lock vault")
        }
    }

    // MARK: - Breadcrumbs

    private var breadcrumbs: some View {
        HStack(spacing: 4) {
            Button {
                viewModel.navigateToRoot()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 10))
                    Text(viewModel.currentMetadata?.vaultName ?? "Root")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.navigationPath.isEmpty ? .primary : Color.accentColor)

            ForEach(Array(viewModel.navigationPath.enumerated()), id: \.element.id) { index, crumb in
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)

                Button {
                    viewModel.navigateToBreadcrumb(index: index)
                } label: {
                    Text(crumb.name)
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(index == viewModel.navigationPath.count - 1 ? .primary : Color.accentColor)
            }

            Spacer()
        }
    }

    // MARK: - Grid View

    private var gridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 16)],
                spacing: 16
            ) {
                ForEach(viewModel.currentFiles) { file in
                    gridItem(file)
                }
            }
            .padding(16)
        }
    }

    private func gridItem(_ file: VaultFileEntry) -> some View {
        let isSelected = viewModel.selectedFileIDs.contains(file.id)

        return VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.08))
                    .frame(width: 80, height: 72)

                Image(systemName: file.iconName)
                    .font(.system(size: 28))
                    .foregroundStyle(file.iconColor)
            }

            Text(file.displayName)
                .font(.system(size: 11))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 100)

            if !file.isFolder {
                Text(file.formattedSize)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : .clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1.5)
        }
        .onTapGesture {
            if file.isFolder {
                viewModel.navigateIntoFolder(file)
            } else {
                if viewModel.selectedFileIDs.contains(file.id) {
                    viewModel.selectedFileIDs.remove(file.id)
                } else {
                    if !NSEvent.modifierFlags.contains(.command) {
                        viewModel.selectedFileIDs = []
                    }
                    viewModel.selectedFileIDs.insert(file.id)
                }
            }
        }
        .onTapGesture(count: 2) {
            if file.isFolder {
                viewModel.navigateIntoFolder(file)
            } else {
                viewModel.previewFileID = file.id
                viewModel.showingPreviewPanel = true
            }
        }
    }

    // MARK: - List View

    private var listView: some View {
        List(viewModel.currentFiles, selection: $viewModel.selectedFileIDs) { file in
            listRow(file)
                .tag(file.id)
                .onTapGesture(count: 2) {
                    if file.isFolder {
                        viewModel.navigateIntoFolder(file)
                    } else {
                        viewModel.previewFileID = file.id
                        viewModel.showingPreviewPanel = true
                    }
                }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func listRow(_ file: VaultFileEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: file.iconName)
                .font(.system(size: 16))
                .foregroundStyle(file.iconColor)
                .frame(width: 24)

            Text(file.displayName)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer()

            Text(file.formattedSize)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)

            Text(file.formattedDate)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))

            Text("Drag files here to encrypt them")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Or use the + button to browse")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)

            Spacer()
        }
    }

    private var noSearchResults: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary.opacity(0.4))

            Text("No files matching \"\(viewModel.searchText)\"")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Text("\(viewModel.totalFileCount) files")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text("·")
                .foregroundStyle(.quaternary)

            Text(viewModel.formattedTotalSize)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            if !viewModel.selectedFileIDs.isEmpty {
                Text("\(viewModel.selectedFileIDs.count) selected")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    UnlockedVaultView(viewModel: {
        let vm = VaultViewModel(engine: MockVaultEngine())
        // Simulate an unlocked vault
        if let id = vm.selectedVaultID {
            vm.vaultStates[id] = .unlocked
            vm.vaultMetadata[id] = MockVaultEngine.makeSampleMetadata(name: "Personal")
        }
        return vm
    }())
    .frame(width: 700, height: 500)
}
