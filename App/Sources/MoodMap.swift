import AiHeartCore
import SwiftData
import SwiftUI

/// Where her mood has been (owner, 2026-11-01): the 2D pad with a soft density of her own
/// mood points over the chosen range, colored by the mood scheme. Recent days as dots.
/// Mood points she placed (or words she picked). Points AiHeart guessed from long writing are drawn hollow
/// until she says they fit (docs/19).
struct MoodMapCard: View {
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @Query private var settingsRows: [AppSettings]
    @State private var days = 30
    @Environment(\.colorScheme) private var scheme

    private var dayStart: Int { settingsRows.first?.dayStartHour ?? 4 }

    private var points: [(v: Double, a: Double, recent: Bool, guessed: Bool)] {
        let today = DayAnchor.day(for: .now, timeZone: .current, dayStartHour: dayStart)
        let from = today.adding(days: -(days - 1)), recentFrom = today.adding(days: -2)
        return entries.compactMap { e in
            guard e.status != .released, let v = e.valence, let a = e.arousal else { return nil }
            let d = DayAnchor.day(for: e.createdAt, timeZone: e.timeZone, dayStartHour: dayStart)
            guard d >= from && d <= today else { return nil }
            return (v, a, d >= recentFrom, e.moodGuessed)
        }
    }

    var body: some View {
        let pts = points
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Where your mood has been").font(.headline).foregroundStyle(Palette.ink)
                Text("Brighter means more entries landed there. Dots: the last 3 days. Hollow ones are AiHeart's guess.").font(.footnote).foregroundStyle(Palette.muted)
            }
            Picker("Range", selection: $days) {
                Text("7 days").tag(7); Text("30 days").tag(30); Text("90 days").tag(90)
            }
            .pickerStyle(.segmented)
            ZStack {
                MoodDensity(points: pts.map { ($0.v, $0.a) }, dark: scheme == .dark)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                GeometryReader { g in
                    let w = g.size.width, h = g.size.height
                    Path { p in p.move(to: CGPoint(x: w / 2, y: 0)); p.addLine(to: CGPoint(x: w / 2, y: h))
                        p.move(to: CGPoint(x: 0, y: h / 2)); p.addLine(to: CGPoint(x: w, y: h / 2)) }
                        .stroke(Palette.line, lineWidth: 1)
                    ForEach(Array(pts.filter(\.recent).enumerated()), id: \.offset) { _, p in
                        Group {
                            if p.guessed {
                                Circle().stroke(Palette.ink.opacity(0.75), lineWidth: 1.5).frame(width: 8, height: 8)
                            } else {
                                Circle().fill(Palette.ink.opacity(0.75)).frame(width: 7, height: 7)
                                    .overlay(Circle().stroke(Palette.card, lineWidth: 1.5))
                            }
                        }
                        .position(x: (p.v + 1) / 2 * w, y: (1 - (p.a + 1) / 2) * h)
                    }
                    Group {
                        Text("stirred").position(x: w / 2, y: 10)
                        Text("still").position(x: w / 2, y: h - 10)
                        Text("unpleasant").position(x: 38, y: h / 2 - 10)
                        Text("pleasant").position(x: w - 30, y: h / 2 - 10)
                    }
                    .font(.caption2).foregroundStyle(Palette.muted)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.line))
            .accessibilityElement()
            .accessibilityLabel(summary(pts))
            Text(summary(pts)).font(.subheadline).foregroundStyle(Palette.muted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func summary(_ pts: [(v: Double, a: Double, recent: Bool, guessed: Bool)]) -> String {
        guard !pts.isEmpty else { return "No mood points in this range yet. Picking a feeling word adds one." }
        let mv = pts.map(\.v).reduce(0, +) / Double(pts.count), ma = pts.map(\.a).reduce(0, +) / Double(pts.count)
        return "Mostly \(MoodColor.words(valence: mv, arousal: ma)), from \(pts.count) entr\(pts.count == 1 ? "y" : "ies")."
    }
}

/// Soft density: each point adds a Gaussian bump; each cell takes the mood color of where
/// it sits, more opaque where more points landed.
struct MoodDensity: View {
    let points: [(Double, Double)]
    let dark: Bool
    private let n = 36

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(dark ? Color.white.opacity(0.03) : Color.white.opacity(0.6)))
            guard !points.isEmpty else { return }
            let sigma = 0.14
            var grid = [Double](repeating: 0, count: n * n)
            for j in 0..<n { for i in 0..<n {
                let x = Double(i) / Double(n - 1) * 2 - 1, y = 1 - Double(j) / Double(n - 1) * 2
                var d = 0.0
                for (v, a) in points { let dx = x - v, dy = y - a; d += exp(-(dx * dx + dy * dy) / (2 * sigma * sigma)) }
                grid[j * n + i] = d
            } }
            let peak = grid.max() ?? 1
            let cw = size.width / CGFloat(n), ch = size.height / CGFloat(n)
            var layer = ctx
            layer.addFilter(.blur(radius: cw * 0.9))
            for j in 0..<n { for i in 0..<n {
                let t = grid[j * n + i] / peak
                guard t > 0.06 else { continue }
                let x = Double(i) / Double(n - 1) * 2 - 1, y = 1 - Double(j) / Double(n - 1) * 2
                let c = MoodColor.color(valence: x, arousal: y)
                let rect = CGRect(x: CGFloat(i) * cw - 1, y: CGFloat(j) * ch - 1, width: cw + 2, height: ch + 2)
                layer.fill(Path(rect), with: .color(Color(red: c.r, green: c.g, blue: c.b).opacity(pow(t, 1.4) * (dark ? 0.9 : 1))))
            } }
        }
    }
}
