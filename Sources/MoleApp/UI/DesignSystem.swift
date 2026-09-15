import SwiftUI

/// Mole design system: dark premium utility aesthetic.
/// Near-black navy backgrounds, warm maintenance accents, cool metric blues,
/// green healthy / amber caution / red destructive — used sparingly.
enum MoleTheme {
    // MARK: Backgrounds

    // MARK: Appearance-adaptive surfaces (Apple guideline: adapt to light/dark)
    // All structural colors resolve via the system appearance so the glass
    // window reads correctly in both modes.

    /// Deepest window background (navy-charcoal / light neutral).
    static let background = Color(NSColor(name: "moleBackground", dynamicProvider: { appearance in
        (appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            ? NSColor(red: 0.075, green: 0.078, blue: 0.09, alpha: 1)
            : NSColor(red: 0.94, green: 0.94, blue: 0.95, alpha: 1)
    }))
    /// Elevated panel base.
    static let panel = Color(NSColor(name: "molePanel", dynamicProvider: { appearance in
        (appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            ? NSColor(red: 0.11, green: 0.115, blue: 0.13, alpha: 1)
            : NSColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)
    }))
    /// Card surface, slightly warmer.
    static let card = Color(NSColor(name: "moleCard", dynamicProvider: { appearance in
        (appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            ? NSColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1)
            : NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.85)
    }))
    /// Warm brown-black used on maintenance views (Clean / Optimize).
    static let warmPanel = Color(NSColor(name: "moleWarmPanel", dynamicProvider: { appearance in
        (appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            ? NSColor(red: 0.13, green: 0.11, blue: 0.095, alpha: 1)
            : NSColor(red: 0.96, green: 0.94, blue: 0.9, alpha: 1)
    }))
    /// Hairline border color.
    static let border = Color(NSColor(name: "moleBorder", dynamicProvider: { appearance in
        ((appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            ? NSColor.white.withAlphaComponent(0.09)
            : NSColor.black.withAlphaComponent(0.1))
    }))
    /// Stronger border for focused elements.
    static let borderStrong = Color(NSColor(name: "moleBorderStrong", dynamicProvider: { appearance in
        ((appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            ? NSColor.white.withAlphaComponent(0.18)
            : NSColor.black.withAlphaComponent(0.22))
    }))

    // MARK: Text

    static let textPrimary = Color(NSColor(name: "moleTextPrimary", dynamicProvider: { appearance in
        ((appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            ? NSColor.white.withAlphaComponent(0.92)
            : NSColor.black.withAlphaComponent(0.88))
    }))
    static let textSecondary = Color(NSColor(name: "moleTextSecondary", dynamicProvider: { appearance in
        ((appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            ? NSColor.white.withAlphaComponent(0.55)
            : NSColor.black.withAlphaComponent(0.55))
    }))
    static let textTertiary = Color(NSColor(name: "moleTextTertiary", dynamicProvider: { appearance in
        ((appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            ? NSColor.white.withAlphaComponent(0.35)
            : NSColor.black.withAlphaComponent(0.38))
    }))

    /// Subtle fill for pills/search fields (white in dark, black in light).
    static let fillSubtle = Color(NSColor(name: "moleFillSubtle", dynamicProvider: { appearance in
        ((appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.black.withAlphaComponent(0.06))
    }))
    /// Strong fill for selected pills.
    static let fillSelected = Color(NSColor(name: "moleFillSelected", dynamicProvider: { appearance in
        ((appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            ? NSColor.white.withAlphaComponent(0.92)
            : NSColor.white.withAlphaComponent(0.95))
    }))

    // MARK: Accents

    /// Mole brand warm amber-brown.
    static let accent = Color(red: 0.96, green: 0.62, blue: 0.28)
    /// Cool blue for informational metrics.
    static let infoBlue = Color(red: 0.42, green: 0.66, blue: 1.0)
    /// Healthy state green.
    static let healthy = Color(red: 0.36, green: 0.82, blue: 0.5)
    /// Caution amber.
    static let caution = Color(red: 0.98, green: 0.75, blue: 0.3)
    /// Destructive / error red.
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.4)

    /// Warm brown/olive variation for maintenance categories.
    static let olive = Color(red: 0.72, green: 0.66, blue: 0.4)

    // MARK: Geometry

    static let cardRadius: CGFloat = 14
    static let largeRadius: CGFloat = 20
    static let pillRadius: CGFloat = 10

    // MARK: Type

    static func metric(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
}

/// Standard card container used across all screens.
struct MoleCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: MoleTheme.cardRadius, style: .continuous)
                    .fill(MoleTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MoleTheme.cardRadius, style: .continuous)
                    .strokeBorder(MoleTheme.border, lineWidth: 1)
            )
    }
}

/// Small uppercase section label.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MoleTheme.textTertiary)
            .tracking(0.6)
    }
}

/// Horizontal capacity bar with semantic coloring and full VoiceOver value.
struct CapacityBar: View {
    /// 0...1
    var fraction: Double
    var color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(color)
                    .frame(width: max(2, geo.size.width * clampedFraction))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private var clampedFraction: Double { min(1, max(0, fraction)) }

    var semanticColor: Color {
        if fraction >= 0.9 { return MoleTheme.danger }
        if fraction >= 0.75 { return MoleTheme.caution }
        return color
    }
}

/// Sparkline used by Status network / CPU / disk history graphs.
struct Sparkline: View {
    var values: [Double]
    var color: Color
    var filled: Bool = true

    var body: some View {
        GeometryReader { geo in
            let path = sparkPath(size: geo.size)
            if filled {
                path
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.35), color.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom))
            }
            path
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true) // values are exposed as text by the parent card
    }

    private func sparkPath(size: CGSize) -> Path {
        var path = Path()
        guard values.count > 1, size.width > 0, size.height > 0 else { return path }
        let maxValue = Swift.max(values.max() ?? 1, 0.0001)
        let stepX = size.width / CGFloat(values.count - 1)

        for (index, value) in values.enumerated() {
            let x = CGFloat(index) * stepX
            let normalized = Swift.min(1, Swift.max(0, value / maxValue))
            let y = size.height - CGFloat(normalized) * (size.height - 2) - 1
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        if filled {
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.closeSubpath()
        }
        return path
    }
}

/// Mole brand silhouette drawn as vector paths — no copyrighted assets.
/// A rounded burrowing-mole profile: body arc, snout, and eye.
struct MoleSilhouette: View {
    var color: Color = MoleTheme.accent
    var eyeColor: Color = MoleTheme.background

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Body: a dome with a pointed snout to the left.
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h * 0.62))
                    path.addCurve(
                        to: CGPoint(x: w, y: h * 0.62),
                        control1: CGPoint(x: w * 0.05, y: h * 0.05),
                        control2: CGPoint(x: w * 0.72, y: h * 0.02))
                    path.addLine(to: CGPoint(x: w, y: h * 0.72))
                    path.addLine(to: CGPoint(x: 0, y: h * 0.72))
                    path.closeSubpath()
                }
                .fill(color)

                // Snout bump.
                Ellipse()
                    .fill(color)
                    .frame(width: w * 0.24, height: h * 0.3)
                    .position(x: w * 0.07, y: h * 0.55)

                // Eye.
                Circle()
                    .fill(eyeColor)
                    .frame(width: w * 0.07, height: w * 0.07)
                    .position(x: w * 0.32, y: h * 0.4)

                // Nose.
                Circle()
                    .fill(eyeColor.opacity(0.75))
                    .frame(width: w * 0.05, height: w * 0.05)
                    .position(x: w * 0.005, y: h * 0.6)
            }
        }
        .aspectRatio(1.5, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

extension Formatter {
    static let byteCount: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

func bytesText(_ bytes: Int64?) -> String {
    guard let bytes else { return "—"
    }
    return Formatter.byteCount.string(fromByteCount: bytes)
}
