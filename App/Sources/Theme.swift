import SwiftUI
import UIKit

/// Semantic colors from design/tokens.json. Dark mode is derived (docs/07): dark plum
/// surfaces, lighter pink actions with dark text, lilac kept at low opacity.
/// Pink means "you", deep rose means "action", lilac means "usual range" or fertile window.
enum Palette {
    static let surface = dynamic(0xFDF8F9, 0x1C1318)
    static let card = dynamic(0xFFFFFF, 0x2A1C23)
    static let line = dynamic(0xF1E6EB, 0x3B2A33)
    static let segment = dynamic(0xF7EDF1, 0x33232B)
    static let ink = dynamic(0x2A1F25, 0xF7EEF2)
    static let muted = dynamic(0x6B5A63, 0xC9B3BF)
    /// Primary action fill.
    static let action = dynamic(0xB5446F, 0xF59BBE)
    /// Text or icon drawn on top of `action`.
    static let onAction = dynamic(0xFFFFFF, 0x1C1318)
    /// Text on pink tints (6.5:1). Never use `action` for this.
    static let onTint = dynamic(0x8F2C57, 0xF59BBE)
    /// Data marks: lines, dots, strokes.
    static let dataMark = dynamic(0xC24578, 0xF59BBE)
    static let pink = dynamic(0xEE8DB3, 0xEE8DB3)
    static let tint1 = dynamic(0xFCE4ED, 0x46263A)
    static let tint2 = dynamic(0xF6CADB, 0x5A2F48)
    static let lilacBand = dynamic(0xEEE3F4, 0x3A2F48)
    static let lilacFertile = dynamic(0xD9CCF0, 0x4B3D63)
    static let flameTint = dynamic(0xFDE8DF, 0x4A2A22)
    static let flame = dynamic(0xF4A27F, 0xF4A27F)
    static let onFlameTint = dynamic(0x8A3B1C, 0xF8C3AA)
    static let phasePeriod = dynamic(0xEE8DB3, 0xC9638D)
    static let phaseFollicular = dynamic(0xFBE0EA, 0x4A2A3A)
    static let phaseLuteal = dynamic(0xF3C3D6, 0x6A3A52)
    static let skeleton = dynamic(0xF3E6EC, 0x33232B)
    static let skeletonHighlight = dynamic(0xFBF1F5, 0x44303A)
    static let figureStroke = dynamic(0xB9809B, 0xD7A3BB)
    static let figureTop = dynamic(0xFDF1F6, 0x3A2531)
    static let figureBottom = dynamic(0xF4D3E0, 0x4E2F40)

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

enum Radius {
    static let card: CGFloat = 20
    static let capture: CGFloat = 28
    static let pill: CGFloat = 22
}

extension Font {
    /// Her own words use a serif (New York). Everything else is the system face.
    static func journal(_ style: Font.TextStyle = .body) -> Font { .system(style, design: .serif) }
}

struct CardBackground: ViewModifier {
    var radius: CGFloat = Radius.card
    func body(content: Content) -> some View {
        content
            .background(Palette.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Palette.line, lineWidth: 1))
    }
}

extension View {
    func card(radius: CGFloat = Radius.card) -> some View { modifier(CardBackground(radius: radius)) }
}

/// Word chip. Selected uses the action fill; unselected is a white pill with a hairline.
struct Chip: View {
    let title: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .fixedSize()
                .font(.body)
                .foregroundStyle(selected ? Palette.onAction : Palette.ink)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(selected ? Palette.action : Palette.card, in: Capsule())
                .overlay(Capsule().stroke(selected ? Color.clear : Palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Small label on a pink tint, e.g. her word on a card.
struct TintLabel: View {
    let text: String
    var tint: Color = Palette.tint1
    var ink: Color = Palette.onTint

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(tint, in: Capsule())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Palette.onAction)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Palette.action.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
    }
}

/// Simple layout that wraps chips onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(maxX, width), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
