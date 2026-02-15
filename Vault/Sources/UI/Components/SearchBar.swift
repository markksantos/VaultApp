// SearchBar.swift
// Vault
//
// Search field for filtering vault contents.

import SwiftUI

public struct SearchBar: View {
    @Binding public var text: String
    public var placeholder: String = "Search files..."

    public init(text: Binding<String>, placeholder: String = "Search files...") {
        self._text = text
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if !text.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        text = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        }
    }
}

#Preview {
    SearchBar(text: .constant("passport"))
        .frame(width: 250)
        .padding()
}
