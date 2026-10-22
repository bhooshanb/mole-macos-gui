import SwiftUI

/// SparkClean design system: dark premium utility aesthetic.
/// Near-black navy backgrounds, warm maintenance accents, cool metric blues,
/// green healthy / amber caution / red destructive — used sparingly.
enum SparkCleanTheme {
    // MARK: Backgrounds

    // MARK: Appearance-adaptive surfaces (Apple guideline: adapt to light/dark)
    // All structural colors resolve via the system appearance so the glass
    // window reads correctly in both modes.

    /// Deepest window background (navy-charcoal / light neutral).
    static let background = Color(NSColor(name: "sparkCleanBackground", dynamicProvider: { appearance in
        (appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            ? NSColor(red: 0.075, green: 0.078, blue: 0.09, alpha: 1)
            : NSColor(red: 0.94, green: 0.94, blue: 0.95, alpha: 1)
    }))
    /// Elevated panel base.
    static let panel = Color(NSColor(name: "sparkCleanPanel", dynamicProvider: { appearance in
        (appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            ? NSColor(red: 0.11, green: 0.115, blue: 0.13, alpha: 1)
            : NSColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)
    }))
    /// Card surface, slightly warmer.
    static let card = Color(NSColor(name: "sparkCleanCard", dynamicProvider: { appearance in
        (appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            ? NSColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1)
            : NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.85)
    }))
    /// Warm brown-black used on maintenance views (Clean / Optimize).
    static let warmPanel = Color(NSColor(name: "sparkCleanWarmPanel", dynamicProvider: { appearance in
        (appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            ? NSColor(red: 0.13, green: 0.11, blue: 0.095, alpha: 1)
            : NSColor(red: 0.96, green: 0.94, blue: 0.9, alpha: 1)
    }))
    /// Hairline border color.
    static let border = Color(NSColor(name: "sparkCleanBorder", dynamicProvider: { appearance in
        ((appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            ? NSColor.white.withAlphaComponent(0.09)
            : NSColor.black.withAlphaComponent(0.1))
    }))
    /// Stronger border for focused elements.
    static let borderStrong = Color(NSColor(name: "sparkCleanBorderStrong", dynamicProvider: { appearance in
        ((appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            ? NSColor.white.withAlphaComponent(0.18)
            : NSColor.black.withAlphaComponent(0.22))
    }))

    // MARK: Text

    static let textPrimary = Color(NSColor(name: "sparkCleanTextPrimary", dynamicProvider: { appearance in
        ((appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            ? NSColor.white.withAlphaComponent(0.92)
            : NSColor.black.withAlphaComponent(0.88))
    }))
    static let textSecondary = Color(NSColor(name: "sparkCleanTextSecondary", dynamicProvider: { appearance in
        ((appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            ? NSColor.white.withAlphaComponent(0.55)
            : NSColor.black.withAlphaComponent(0.55))
    }))
    static let textTertiary = Color(NSColor(name: "sparkCleanTextTertiary", dynamicProvider: { appearance in
        ((appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            ? NSColor.white.withAlphaComponent(0.35)
            : NSColor.black.withAlphaComponent(0.38))
    }))

    /// Subtle fill for pills/search fields (white in dark, black in light).
    static let fillSubtle = Color(NSColor(name: "sparkCleanFillSubtle", dynamicProvider: { appearance in
        ((appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.black.withAlphaComponent(0.06))
    }))
    /// Strong fill for selected pills.
    static let fillSelected = Color(NSColor(name: "sparkCleanFillSelected", dynamicProvider: { appearance in
        ((appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            ? NSColor.white.withAlphaComponent(0.92)
            : NSColor.white.withAlphaComponent(0.95))
    }))

    // MARK: Accents

    /// SparkClean brand electric blue-violet.
    static let accent = Color(red: 0.55, green: 0.45, blue: 1.0)
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
struct SparkCleanCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: SparkCleanTheme.cardRadius, style: .continuous)
                    .fill(SparkCleanTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SparkCleanTheme.cardRadius, style: .continuous)
                    .strokeBorder(SparkCleanTheme.border, lineWidth: 1)
            )
    }
}

/// Small uppercase section label.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(SparkCleanTheme.textTertiary)
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
        if fraction >= 0.9 { return SparkCleanTheme.danger }
        if fraction >= 0.75 { return SparkCleanTheme.caution }
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

/// SparkClean brand sparkle mark drawn as vector paths — no copyrighted assets.
/// A four-point sparkle burst: one large star with two satellite sparkles.
struct SparkleMark: View {
    var color: Color = SparkCleanTheme.accent

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // Primary four-point sparkle, centered.
                SparklePath()
                    .fill(color)
                    .frame(width: s * 0.68, height: s * 0.68)
                    .position(x: geo.size.width * 0.5, y: geo.size.height * 0.5)

                // Upper-right satellite sparkle.
                SparklePath()
                    .fill(color.opacity(0.85))
                    .frame(width: s * 0.3, height: s * 0.3)
                    .position(x: geo.size.width * 0.86, y: geo.size.height * 0.2)

                // Lower-left satellite sparkle.
                SparklePath()
                    .fill(color.opacity(0.7))
                    .frame(width: s * 0.22, height: s * 0.22)
                    .position(x: geo.size.width * 0.16, y: geo.size.height * 0.84)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// A four-point sparkle: four convex points joined by concave quadratic curves.
struct SparklePath: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        // Distance from center where the curve pinches inward.
        let pinch = r * 0.22
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - r))
        path.addQuadCurve(
            to: CGPoint(x: center.x + r, y: center.y),
            control: CGPoint(x: center.x + pinch, y: center.y - pinch))
        path.addQuadCurve(
            to: CGPoint(x: center.x, y: center.y + r),
            control: CGPoint(x: center.x + pinch, y: center.y + pinch))
        path.addQuadCurve(
            to: CGPoint(x: center.x - r, y: center.y),
            control: CGPoint(x: center.x - pinch, y: center.y + pinch))
        path.addQuadCurve(
            to: CGPoint(x: center.x, y: center.y - r),
            control: CGPoint(x: center.x - pinch, y: center.y - pinch))
        path.closeSubpath()
        return path
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
