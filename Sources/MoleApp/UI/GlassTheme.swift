import SwiftUI
import AppKit

/// Apple "Liquid Glass" theming (macOS 26+) with a graceful fallback to the
/// existing dark surfaces on older systems.
enum GlassTheme {
    /// True on macOS 26+ where the glass APIs exist.
    static let isAvailable: Bool = {
        if #available(macOS 26.0, *) { return true }
        return false
    }()

    /// Window background: clear when glass shows through, opaque otherwise.
    static var windowBackground: Color {
        isAvailable ? .clear : MoleTheme.background
    }

    /// Panel background color for popups and sheets.
    static var panelBackground: Color {
        isAvailable ? MoleTheme.panel.opacity(0.72) : MoleTheme.panel
    }
}

// MARK: - Window chrome

/// Applies macOS 26 Liquid Glass window chrome to a borderless-style window:
/// the whole window becomes a rounded glass slab; content draws on top.
@MainActor
enum GlassWindowChrome {
    static func apply(to window: NSWindow) {
        // Keep the standard .titled style so the traffic lights stay native
        // (Apple guideline: use full-size content view rather than removing
        // the titled mask when standard window buttons are wanted).
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true

        if #available(macOS 26.0, *) {
            // Full glass: clear window body, glass slab behind all content.
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true

            guard let content = window.contentView, !(content is NSGlassEffectView) else { return }
            let glass = NSGlassEffectView(frame: window.contentLayoutRect)
            glass.cornerRadius = 22
            glass.autoresizingMask = [.width, .height]
            // Tint adapts with system appearance; nil lets glass track it.
            glass.tintColor = nil
            glass.contentView = content
            window.contentView = glass
        } else {
            // Pre-26: edge-to-edge content, opaque themed background.
            window.backgroundColor = .windowBackgroundColor
        }
    }
}

// MARK: - SwiftUI modifiers

/// Window-level background: transparent on glass-capable systems so the
/// window chrome's glass shows through; otherwise the standard dark theme.
struct GlassWindowBackground: ViewModifier {
    func body(content: Content) -> some View {
        if GlassTheme.isAvailable {
            content.background(Color.clear)
        } else {
            content.background(MoleTheme.background)
        }
    }
}

/// Card surface: real glass effect on macOS 26+, the standard card below.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(MoleTheme.card))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(MoleTheme.border, lineWidth: 1))
        }
    }
}

extension View {
    /// Window background appropriate for the glass theme.
    func glassWindowBackground() -> some View {
        modifier(GlassWindowBackground())
    }

    /// Liquid-glass card surface with automatic fallback.
    func glassCard(cornerRadius: CGFloat = 14) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}
