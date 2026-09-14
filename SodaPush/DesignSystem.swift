import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum SodaDate {
    static func formatted(_ value: String?, dateOnly: Bool = false) -> String {
        guard let value, let date = ISO8601DateFormatter().date(from: value) else { return "—" }
        return date.formatted(date: dateOnly ? .abbreviated : .abbreviated, time: dateOnly ? .omitted : .shortened)
    }
}

enum SodaClipboard {
    static func copy(_ value: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #else
        UIPasteboard.general.string = value
        #endif
    }
}

struct StatusBadge: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityLabel("Status: \(text)")
    }

    static func color(for status: String) -> Color {
        switch status.lowercased() {
        case "active", "completed", "ready": .green
        case "queued", "running", "development": .blue
        case "partial": .orange
        case "failed", "invalid", "inactive", "disabled", "not_ready": .red
        case "production": .purple
        default: .secondary
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
            Text(value)
                .font(.title.bold())
                .contentTransition(.numericText())
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct InlineErrorView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button("Retry", action: retry)
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

extension AppRole {
    var title: String { rawValue.capitalized }
    var tint: Color {
        switch self {
        case .owner: .purple
        case .admin: .blue
        case .developer: .teal
        case .viewer: .secondary
        }
    }
}
