import Foundation

/// A color for a mood point (owner, 2026-11-01), blended between four corner colors chosen
/// from common color associations: warm apricot for pleasant and stirred, soft sage for
/// pleasant and still, muted amber for unpleasant and stirred, dusty blue for unpleasant and
/// still, pale blush near the middle. No red (CLAUDE.md #4). Never the only carrier of meaning.
public enum MoodColor {
    public struct RGB: Equatable, Sendable {
        public let r: Double, g: Double, b: Double
        public init(_ hex: UInt32) {
            r = Double((hex >> 16) & 0xFF) / 255; g = Double((hex >> 8) & 0xFF) / 255; b = Double(hex & 0xFF) / 255
        }
        init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
        func mix(_ o: RGB, _ t: Double) -> RGB { RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t) }
    }

    public static let excited = RGB(0xF6B48B)   // pleasant, stirred
    public static let calm = RGB(0xA9D3B8)      // pleasant, still
    public static let tense = RGB(0xE6C27A)     // unpleasant, stirred
    public static let low = RGB(0x9EB4D6)       // unpleasant, still
    public static let neutral = RGB(0xF6DCE5)   // middle

    public static func color(valence v: Double, arousal a: Double) -> RGB {
        let x = (max(-1, min(1, v)) + 1) / 2, y = (max(-1, min(1, a)) + 1) / 2
        let top = tense.mix(excited, x)
        let bottom = low.mix(calm, x)
        let corner = bottom.mix(top, y)
        // Near the middle the color fades toward blush.
        let strength = min(1, sqrt(v * v + a * a) / 0.6)
        return neutral.mix(corner, strength)
    }

    /// Plain words for VoiceOver, so color is never the only signal.
    public static func words(valence v: Double, arousal a: Double) -> String {
        if abs(v) < 0.15 && abs(a) < 0.15 { return "near neutral" }
        let p = v > 0.15 ? "pleasant" : v < -0.15 ? "unpleasant" : ""
        let s = a > 0.15 ? "stirred" : a < -0.15 ? "still" : ""
        return [p, s].filter { !$0.isEmpty }.joined(separator: " and ")
    }

    /// Hue in degrees, for the no-red check.
    public static func hue(_ c: RGB) -> Double {
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b), d = mx - mn
        guard d > 1e-9 else { return 0 }
        var h: Double
        if mx == c.r { h = ((c.g - c.b) / d).truncatingRemainder(dividingBy: 6) }
        else if mx == c.g { h = (c.b - c.r) / d + 2 }
        else { h = (c.r - c.g) / d + 4 }
        h *= 60
        return h < 0 ? h + 360 : h
    }
}
