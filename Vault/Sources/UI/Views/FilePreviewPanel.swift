// FilePreviewPanel.swift
// Vault
//
// Quick Look-style preview panel for vault files. Decrypts to memory only.

import SwiftUI

public struct FilePreviewPanel: View {
    @Bindable public var viewModel: VaultViewModel

    @State private var previewData: Data?
    @State private var isLoading: Bool = false
    @State private var loadError: String?

    public init(viewModel: VaultViewModel) {
        self.viewModel = viewModel
    }

    private var file: VaultFileEntry? {
        guard let fileID = viewModel.previewFileID,
              let metadata = viewModel.currentMetadata else { return nil }
        return metadata.files.first { $0.id == fileID }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Preview content
            if isLoading {
                loadingView
            } else if let error = loadError {
                errorView(error)
            } else if let data = previewData, let file = file {
                previewContent(data: data, file: file)
            } else {
                placeholderView
            }

            Divider()

            // File info footer
            if let file = file {
                fileInfoFooter(file)
            }
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
        .background(.ultraThinMaterial)
        .onChange(of: viewModel.previewFileID) {
            loadPreview()
        }
        .onAppear {
            loadPreview()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if let file = file {
                Image(systemName: file.iconName)
                    .foregroundStyle(file.iconColor)
                Text(file.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            } else {
                Text("Preview")
                    .font(.system(size: 13, weight: .medium))
            }

            Spacer()

            Button {
                viewModel.showingPreviewPanel = false
                viewModel.previewFileID = nil
                previewData = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Preview Content

    @ViewBuilder
    private func previewContent(data: Data, file: VaultFileEntry) -> some View {
        ScrollView {
            VStack {
                switch file.originalExtension.lowercased() {
                case "jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "bmp":
                    imagePreview(data)

                case "txt", "md", "rtf", "csv", "json", "xml", "html", "css", "js", "swift", "py":
                    textPreview(data)

                case "pdf":
                    pdfPlaceholder(file)

                default:
                    genericPreview(file, data: data)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(12)
        }
    }

    @ViewBuilder
    private func imagePreview(_ data: Data) -> some View {
        if let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            genericFileIcon
        }
    }

    @ViewBuilder
    private func textPreview(_ data: Data) -> some View {
        if let text = String(data: data, encoding: .utf8) {
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.black.opacity(0.3))
                }
                .textSelection(.enabled)
        } else {
            genericFileIcon
        }
    }

    private func pdfPlaceholder(_ file: VaultFileEntry) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.system(size: 40))
                .foregroundStyle(.red)
            Text(file.displayName)
                .font(.system(size: 13, weight: .medium))
            Text("PDF preview — decrypted in memory")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 40)
    }

    private func genericPreview(_ file: VaultFileEntry, data: Data) -> some View {
        VStack(spacing: 12) {
            Image(systemName: file.iconName)
                .font(.system(size: 40))
                .foregroundStyle(file.iconColor)
            Text(file.displayName)
                .font(.system(size: 13, weight: .medium))
            Text(file.formattedSize)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Binary file — no preview available")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 40)
    }

    private var genericFileIcon: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Unable to preview")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 40)
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("Decrypting...")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text("Preview Failed")
                .font(.system(size: 14, weight: .medium))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(16)
    }

    private var placeholderView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "eye.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("Select a file to preview")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - File Info Footer

    private func fileInfoFooter(_ file: VaultFileEntry) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Size")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text(file.formattedSize)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Modified")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text(file.formattedDate)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Export") {
                Task { await viewModel.exportSelectedFiles() }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Load Preview

    private func loadPreview() {
        guard let fileID = viewModel.previewFileID else {
            previewData = nil
            return
        }

        isLoading = true
        loadError = nil
        previewData = nil

        Task {
            let data = await viewModel.previewFile(id: fileID)
            if data == nil {
                loadError = "Failed to load file preview."
            }
            previewData = data
            isLoading = false
        }
    }
}

#Preview {
    FilePreviewPanel(viewModel: {
        let vm = VaultViewModel(engine: MockVaultEngine())
        if let id = vm.selectedVaultID {
            vm.vaultStates[id] = .unlocked
            vm.vaultMetadata[id] = MockVaultEngine.makeSampleMetadata(name: "Personal")
            vm.previewFileID = MockVaultEngine.sampleFiles.first?.id
        }
        return vm
    }())
    .frame(height: 500)
}
