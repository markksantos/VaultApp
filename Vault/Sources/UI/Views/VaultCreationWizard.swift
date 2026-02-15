// VaultCreationWizard.swift
// Vault
//
// Multi-step vault creation sheet: name, password, Touch ID, storage location, preferences.

import SwiftUI

public struct VaultCreationWizard: View {
    @Bindable public var viewModel: VaultViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep: Int = 0
    @State private var vaultName: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var enableTouchID: Bool = true
    @State private var storageLocation: URL = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory).appendingPathComponent("Vault")
    @State private var deleteOriginals: Bool = false
    @State private var isCreating: Bool = false

    private let totalSteps = 5

    public init(viewModel: VaultViewModel) {
        self.viewModel = viewModel
    }

    private var canAdvance: Bool {
        switch currentStep {
        case 0: return !vaultName.trimmingCharacters(in: .whitespaces).isEmpty
        case 1: return !password.isEmpty && password == confirmPassword && PasswordStrength.evaluate(password) >= .fair
        case 2: return true
        case 3: return true
        case 4: return true
        default: return false
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressBar
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 24)

            // Step content
            Group {
                switch currentStep {
                case 0: nameStep
                case 1: passwordStep
                case 2: touchIDStep
                case 3: locationStep
                case 4: preferencesStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 32)

            Divider()

            // Navigation buttons
            navigationButtons
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(width: 480, height: 440)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<totalSteps, id: \.self) { step in
                RoundedRectangle(cornerRadius: 2)
                    .fill(step <= currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.25), value: currentStep)
            }
        }
    }

    // MARK: - Step 1: Name

    private var nameStep: some View {
        VStack(spacing: 16) {
            stepHeader(icon: "lock.shield.fill", title: "Name Your Vault", subtitle: "Choose a name to identify this vault.")

            TextField("Vault name", text: $vaultName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))

            Spacer()
        }
    }

    // MARK: - Step 2: Password

    private var passwordStep: some View {
        VStack(spacing: 16) {
            stepHeader(icon: "key.fill", title: "Set a Password", subtitle: "This password encrypts your vault. Choose a strong one — it cannot be recovered.")

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))

            PasswordStrengthIndicator(password: password)

            SecureField("Confirm password", text: $confirmPassword)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))

            if !confirmPassword.isEmpty && password != confirmPassword {
                Label("Passwords do not match", systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
    }

    // MARK: - Step 3: Touch ID

    private var touchIDStep: some View {
        VStack(spacing: 16) {
            stepHeader(icon: "touchid", title: "Enable Touch ID?", subtitle: "Use Touch ID for quick unlock. Your password is still required as a fallback.")

            Toggle(isOn: $enableTouchID) {
                HStack(spacing: 12) {
                    Image(systemName: "touchid")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Touch ID Unlock")
                            .font(.system(size: 14, weight: .medium))
                        Text("Securely store key in Keychain with biometric protection")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.switch)
            .padding(.vertical, 8)

            Spacer()
        }
    }

    // MARK: - Step 4: Storage Location

    private var locationStep: some View {
        VStack(spacing: 16) {
            stepHeader(icon: "folder.fill", title: "Storage Location", subtitle: "Choose where to save the encrypted vault container file.")

            HStack {
                Text(storageLocation.path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Choose...") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    if panel.runModal() == .OK, let url = panel.url {
                        storageLocation = url
                    }
                }
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
            }

            Text("Default: ~/Library/Application Support/Vault/")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Step 5: Preferences

    private var preferencesStep: some View {
        VStack(spacing: 16) {
            stepHeader(icon: "gearshape.fill", title: "Preferences", subtitle: "Configure how the vault handles imported files.")

            Toggle(isOn: $deleteOriginals) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Securely delete originals after adding")
                        .font(.system(size: 14, weight: .medium))
                    Text("Original files are overwritten and removed after encryption. This cannot be undone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(.vertical, 8)

            // Summary
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    summaryRow("Name", value: vaultName)
                    summaryRow("Touch ID", value: enableTouchID ? "Enabled" : "Disabled")
                    summaryRow("Location", value: storageLocation.lastPathComponent)
                    summaryRow("Delete originals", value: deleteOriginals ? "Yes" : "No")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Summary", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            if currentStep > 0 {
                Button("Back") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentStep -= 1
                    }
                }
            }

            if currentStep < totalSteps - 1 {
                Button("Next") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentStep += 1
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdvance)
            } else {
                Button {
                    createVault()
                } label: {
                    HStack(spacing: 6) {
                        if isCreating {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isCreating ? "Creating..." : "Create Vault")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isCreating)
            }
        }
    }

    // MARK: - Helpers

    private func stepHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(Color.accentColor)

            Text(title)
                .font(.system(size: 18, weight: .semibold))

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }

    private func createVault() {
        isCreating = true
        Task {
            let sanitizedName = vaultName.trimmingCharacters(in: .whitespaces)
            let vaultFilePath = storageLocation.appendingPathComponent("\(sanitizedName).vault")
            await viewModel.createVault(
                name: sanitizedName,
                password: password,
                at: vaultFilePath,
                touchIDEnabled: enableTouchID
            )
            isCreating = false
            dismiss()
        }
    }
}

#Preview {
    VaultCreationWizard(viewModel: VaultViewModel(engine: MockVaultEngine()))
}
