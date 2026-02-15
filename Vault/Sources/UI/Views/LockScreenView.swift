// LockScreenView.swift
// Vault
//
// Dark, minimal lock screen with password field, Touch ID, and shake animation on failure.

import SwiftUI

public struct LockScreenView: View {
    @Bindable public var viewModel: VaultViewModel

    @State private var password: String = ""
    @State private var shakeOffset: CGFloat = 0
    @State private var isUnlocking: Bool = false
    @State private var showFailedMessage: Bool = false

    public init(viewModel: VaultViewModel) {
        self.viewModel = viewModel
    }

    private var vault: VaultInfo? { viewModel.selectedVault }
    private var isLocked: Bool { viewModel.selectedVaultState == .locked }

    public var body: some View {
        ZStack {
            // Dark gradient background
            LinearGradient(
                colors: [
                    Color.black,
                    Color(white: 0.08),
                    Color(white: 0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Lock icon
                lockIcon
                    .padding(.bottom, 24)

                // Vault name
                Text(vault?.name ?? "Vault")
                    .font(.system(size: 28, weight: .bold, design: .default))
                    .foregroundStyle(.white)
                    .padding(.bottom, 8)

                Text("Enter password to unlock")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 32)

                // Password field + unlock
                passwordSection
                    .offset(x: shakeOffset)
                    .padding(.bottom, 16)

                // Touch ID button
                if vault?.touchIDEnabled == true {
                    touchIDButton
                        .padding(.bottom, 16)
                }

                // Failed attempt feedback
                if showFailedMessage {
                    failedAttemptLabel
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer()

                // Branding
                Text("VAULT")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.15))
                    .tracking(4)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: 340)
        }
    }

    // MARK: - Lock Icon

    private var lockIcon: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.05))
                .frame(width: 80, height: 80)

            Image(systemName: isUnlocking ? "lock.rotation" : "lock.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .symbolEffect(.pulse, isActive: isUnlocking)
        }
    }

    // MARK: - Password Section

    private var passwordSection: some View {
        VStack(spacing: 12) {
            SecureField("Password", text: $password)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.08))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                }
                .onSubmit { attemptUnlock() }
                .disabled(isUnlocking)

            Button(action: attemptUnlock) {
                HStack(spacing: 6) {
                    if isUnlocking {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text(isUnlocking ? "Unlocking..." : "Unlock")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(password.isEmpty ? .white.opacity(0.05) : .white.opacity(0.15))
                }
                .foregroundStyle(password.isEmpty ? .white.opacity(0.3) : .white)
            }
            .buttonStyle(.plain)
            .disabled(password.isEmpty || isUnlocking)
        }
    }

    // MARK: - Touch ID Button

    private var touchIDButton: some View {
        Button {
            Task { await attemptTouchID() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "touchid")
                    .font(.system(size: 18))
                Text("Unlock with Touch ID")
                    .font(.system(size: 13))
            }
            .foregroundStyle(.white.opacity(0.6))
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background {
                Capsule()
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isUnlocking)
    }

    // MARK: - Failed Attempt Label

    private var failedAttemptLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
            Text("Incorrect password")
                .font(.system(size: 12))
            if viewModel.failedAttempts > 1 {
                Text("(\(viewModel.failedAttempts) attempts)")
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.7))
            }
        }
        .foregroundStyle(.red.opacity(0.9))
    }

    // MARK: - Actions

    private func attemptUnlock() {
        guard !password.isEmpty, !isUnlocking else { return }
        isUnlocking = true
        showFailedMessage = false

        Task {
            await viewModel.unlockVault(password: password)
            isUnlocking = false

            if viewModel.selectedVaultState != .unlocked {
                triggerShake()
                withAnimation(.easeInOut(duration: 0.3)) {
                    showFailedMessage = true
                }
                password = ""
            }
        }
    }

    private func attemptTouchID() async {
        isUnlocking = true
        showFailedMessage = false
        await viewModel.unlockWithTouchID()
        isUnlocking = false

        if viewModel.selectedVaultState != .unlocked {
            withAnimation(.easeInOut(duration: 0.3)) {
                showFailedMessage = true
            }
        }
    }

    private func triggerShake() {
        withAnimation(.default) { shakeOffset = -12 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.default) { shakeOffset = 10 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.default) { shakeOffset = -6 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.default) { shakeOffset = 4 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { shakeOffset = 0 }
        }
    }
}

#Preview {
    LockScreenView(viewModel: VaultViewModel(engine: MockVaultEngine()))
        .frame(width: 600, height: 500)
}
