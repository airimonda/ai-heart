import Foundation

// Her safety plan, in the six steps of the Stanley-Brown Safety Planning Intervention (docs/17-safety-plan.md),
// plus "Anything else" (the old free-text safety page, kept so nothing she wrote is lost).
// Everything on it is written by her. Nothing here is ever generated. Fixed titles and helper lines only.

public enum SafetyPlan {
    public enum Step: Int, CaseIterable, Sendable {
        case signs = 1, coping, places, helpers, pros, safeSpace, other

        public var title: String {
            switch self {
            case .signs: "My warning signs"
            case .coping: "Things I can do on my own"
            case .places: "People and places that help me feel better"
            case .helpers: "People I can ask for help"
            case .pros: "Professionals I can call"
            case .safeSpace: "Making my space safer"
            case .other: "Anything else"
            }
        }

        public var helper: String {
            switch self {
            case .signs: "Thoughts, feelings and situations that tell you a crisis may be coming."
            case .coping: "Things that take your mind off it, which you can do by yourself."
            case .places: "People or places that give you company or a change of scene."
            case .helpers: "People you can ask for help. Their names and numbers."
            case .pros: "Your therapist, a clinic, crisis lines. Names and numbers."
            case .safeSpace: "Ways to make the place you are in safer."
            case .other: "Anything that does not fit above."
            }
        }

        /// The text she wrote for this step.
        public func text(in s: AppSettings) -> String {
            switch self {
            case .signs: s.planSigns
            case .coping: s.planCoping
            case .places: s.planPlaces
            case .helpers: s.planHelpers
            case .pros: s.planPros
            case .safeSpace: s.planSafeSpace
            case .other: s.safetyPage
            }
        }

        public func set(_ value: String, in s: AppSettings) {
            switch self {
            case .signs: s.planSigns = value
            case .coping: s.planCoping = value
            case .places: s.planPlaces = value
            case .helpers: s.planHelpers = value
            case .pros: s.planPros = value
            case .safeSpace: s.planSafeSpace = value
            case .other: s.safetyPage = value
            }
        }
    }

    public struct Section: Identifiable, Equatable, Sendable {
        public let step: Step
        public let title: String
        public let text: String
        public var id: Int { step.rawValue }
    }

    /// The steps she has written, in order, with her text trimmed. Empty steps are left out unless
    /// `includeEmpty` is true.
    public static func sections(from s: AppSettings, includeEmpty: Bool = false) -> [Section] {
        Step.allCases.compactMap { step in
            let text = step.text(in: s).trimmingCharacters(in: .whitespacesAndNewlines)
            guard includeEmpty || !text.isEmpty else { return nil }
            return Section(step: step, title: step.title, text: text)
        }
    }

    /// Plain text, one block per written step, for places that only take a string.
    public static func plainText(from s: AppSettings) -> String {
        sections(from: s).map { "\($0.title)\n\($0.text)" }.joined(separator: "\n\n")
    }

    // MARK: Phone numbers

    /// A phone number found in her text: digits with optional +, spaces, dashes, dots or brackets,
    /// 3 to 15 digits in all. Simple on purpose. Tapping one opens the Phone prompt; nothing dials by itself.
    public struct PhoneMatch: Equatable, Sendable {
        public let range: Range<String.Index>
        public let url: URL
    }

    private static let phonePattern = #"(?<![\w+])\+?(?:\(\d{1,4}\)[ .-]?)?\d(?:[ .-]?\d){2,}(?![\w])"#

    public static func phoneMatches(in text: String) -> [PhoneMatch] {
        guard let regex = try? NSRegularExpression(pattern: phonePattern) else { return [] }
        let ns = text as NSString
        var out: [PhoneMatch] = []
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let r = Range(m.range, in: text) else { continue }
            let raw = String(text[r])
            let digits = raw.filter(\.isASCII).filter(\.isNumber)
            guard (3...15).contains(digits.count) else { continue }
            // A date such as 2026-11-04 is not a number to ring.
            if raw.range(of: #"^\d{4}[-.]\d{1,2}[-.]\d{1,2}$"#, options: .regularExpression) != nil { continue }
            let number = (raw.hasPrefix("+") ? "+" : "") + digits
            guard let url = URL(string: "tel:\(number)") else { continue }
            out.append(PhoneMatch(range: r, url: url))
        }
        return out
    }

    /// Her text with each phone number made a `tel:` link.
    public static func linkified(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        for m in phoneMatches(in: text) {
            if let lo = AttributedString.Index(m.range.lowerBound, within: attr),
               let hi = AttributedString.Index(m.range.upperBound, within: attr) {
                attr[lo..<hi].link = m.url
            }
        }
        return attr
    }
}
