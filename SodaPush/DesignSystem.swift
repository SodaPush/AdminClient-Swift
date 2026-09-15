import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum SodaDate {
    static func formatted(_ value: String?, dateOnly: Bool = false) -> String {
        guard let value, let date = parsed(value) else { return "—" }
        return date.formatted(date: dateOnly ? .abbreviated : .abbreviated, time: dateOnly ? .omitted : .shortened)
    }

    private static func parsed(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

extension View {
    @ViewBuilder
    func sodaSheetFrame(minHeight: CGFloat = 560) -> some View {
        #if os(macOS)
        frame(minWidth: 540, minHeight: minHeight)
        #else
        self
        #endif
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

struct SodaBrandIcon: View {
    var size: CGFloat = 72

    var body: some View {
        Group {
            #if os(macOS)
            Image(nsImage: appIcon)
                .resizable()
                .scaledToFit()
            #else
            if let appIcon = UIImage(named: "AppIcon") ?? UIImage(named: "AppIcon60x60") {
                Image(uiImage: appIcon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "bell.and.waves.left.and.right.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.tint)
            }
            #endif
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityLabel("SodaPush app icon")
    }

    #if os(macOS)
    private var appIcon: NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOfFile: url.path) {
            return icon
        }
        return NSApplication.shared.applicationIconImage
    }
    #endif
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
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            Text(value)
                .font(.title.bold())
                .contentTransition(.numericText())
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.06)))
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
