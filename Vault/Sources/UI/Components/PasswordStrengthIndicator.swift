// PasswordStrengthIndicator.swift
// Vault
//
// Visual password strength meter with colored bar and descriptive label.

import SwiftUI

// MARK: - Strength Level

public enum PasswordStrength: Int, Comparable {
    case empty = 0
    case weak = 1
    case fair = 2
    case strong = 3
    case veryStrong = 4

    public static func < (lhs: PasswordStrength, rhs: PasswordStrength) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .empty: return ""
        case .weak: return "Weak"
        case .fair: return "Fair"
        case .strong: return "Strong"
        case .veryStrong: return "Very Strong"
        }
    }

    public var color: Color {
        switch self {
        case .empty: return .gray.opacity(0.3)
        case .weak: return .red
        case .fair: return .orange
        case .strong: return .yellow
        case .veryStrong: return .green
        }
    }

    public var fillFraction: Double {
        switch self {
        case .empty: return 0
        case .weak: return 0.25
        case .fair: return 0.5
        case .strong: return 0.75
        case .veryStrong: return 1.0
        }
    }

    public static func evaluate(_ password: String) -> PasswordStrength {
        guard !password.isEmpty else { return .empty }

        var score = 0

        // Length scoring
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.count >= 16 { score += 1 }

        // Character variety
        let hasLowercase = password.range(of: "[a-z]", options: .regularExpression) != nil
        let hasUppercase = password.range(of: "[A-Z]", options: .regularExpression) != nil
        let hasDigit = password.range(of: "[0-9]", options: .regularExpression) != nil
        let hasSymbol = password.range(of: "[^a-zA-Z0-9]", options: .regularExpression) != nil

        if hasLowercase && hasUppercase { score += 1 }
        if hasDigit { score += 1 }
        if hasSymbol { score += 1 }

        switch score {
        case 0...1: return .weak
        case 2...3: return .fair
        case 4...5: return .strong
        default: return .veryStrong
        }
    }
}

// MARK: - View

public struct PasswordStrengthIndicator: View {
    public let password: String

    public init(password: String) {
        self.password = password
    }

    private var strength: PasswordStrength {
        PasswordStrength.evaluate(password)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)

                    // Filled portion
                    RoundedRectangle(cornerRadius: 3)
                        .fill(strength.color)
                        .frame(width: geometry.size.width * strength.fillFraction, height: 6)
                        .animation(.easeInOut(duration: 0.3), value: strength)
                }
            }
            .frame(height: 6)

            if strength != .empty {
                Text(strength.label)
                    .font(.caption)
                    .foregroundStyle(strength.color)
                    .animation(.easeInOut(duration: 0.2), value: strength)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        PasswordStrengthIndicator(password: "")
        PasswordStrengthIndicator(password: "abc")
        PasswordStrengthIndicator(password: "abcdef12")
        PasswordStrengthIndicator(password: "Abcdef123!")
        PasswordStrengthIndicator(password: "MyStr0ng!P@ssw0rd")
    }
    .padding()
    .frame(width: 300)
}
