// VaultApp.swift
// Vault
//
// @main app entry point with NavigationSplitView, AppDelegate, and menu commands.

import SwiftUI
import VaultCore

@main
struct VaultApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var viewModel = VaultViewModel(engine: VaultEngine())
    private let panicLock = PanicLockManager()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 800, minHeight: 500)
                .preferredColorScheme(.dark)
                .task {
                    await viewModel.discoverVaults()
                    panicLock.register { [viewModel] in
                        await viewModel.lockAllVaults()
                    }
                }
                .onOpenURL { url in
                    handleVaultURL(url)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1000, height: 650)
        .commands {
            vaultCommands
        }
    }

    // MARK: - URL Scheme Handler

    private func handleVaultURL(_ url: URL) {
        guard url.scheme == "vault", url.host == "add" else { return }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let filesParam = components.queryItems?.first(where: { $0.name == "files" })?.value,
              let jsonData = filesParam.data(using: .utf8),
              let paths = try? JSONDecoder().decode([String].self, from: jsonData)
        else { return }

        let fileURLs = paths.map { URL(fileURLWithPath: $0) }
        guard !fileURLs.isEmpty else { return }

        Task {
            await viewModel.addFiles(urls: fileURLs)
        }
    }

    // MARK: - Menu Commands

    @CommandsBuilder
    private var vaultCommands: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Vault...") {
                viewModel.showingCreationWizard = true
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("Lock All Vaults") {
                Task { await viewModel.lockAllVaults() }
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure vault storage directory exists
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let vaultDir = appSupport.appendingPathComponent("Vault")
        try? FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillResignActive(_ notification: Notification) {
        // Could trigger auto-lock here via notification
        NotificationCenter.default.post(name: .vaultAppDidResignActive, object: nil)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let vaultAppDidResignActive = Notification.Name("vaultAppDidResignActive")
}

// MARK: - Content View

struct ContentView: View {
    @Bindable var viewModel: VaultViewModel

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VaultListSidebar(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            detailView
        }
        .sheet(isPresented: $viewModel.showingCreationWizard) {
            VaultCreationWizard(viewModel: viewModel)
        }
        .alert(
            "Error",
            isPresented: $viewModel.showError,
            presenting: viewModel.currentError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.errorDescription ?? "An unknown error occurred.")
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if viewModel.selectedVault == nil {
            noVaultSelected
        } else {
            switch viewModel.selectedVaultState {
            case .locked, .unlocking:
                LockScreenView(viewModel: viewModel)

            case .unlocked, .locking:
                HStack(spacing: 0) {
                    UnlockedVaultView(viewModel: viewModel)

                    if viewModel.showingPreviewPanel {
                        Divider()
                        FilePreviewPanel(viewModel: viewModel)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: viewModel.showingPreviewPanel)
            }
        }
    }

    private var noVaultSelected: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.3))

            Text("Select a vault")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Choose a vault from the sidebar, or create a new one.")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)

            Button {
                viewModel.showingCreationWizard = true
            } label: {
                Label("Create New Vault", systemImage: "plus.circle.fill")
            }
            .controlSize(.large)
        }
    }
}

#Preview {
    ContentView(viewModel: VaultViewModel(engine: MockVaultEngine()))
        .frame(width: 900, height: 600)
}
