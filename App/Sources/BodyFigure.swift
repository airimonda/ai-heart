import AiHeartCore
import SwiftUI

/// The body figure, drawn natively as one smooth closed outline.
/// All coordinates are in the original SVG's viewBox (105 25 486 1290), which the hit regions also use.
enum FigureGeometry {
    static let viewBox = CGRect(x: 105, y: 25, width: 486, height: 1290)

    /// Left half of the outline, clockwise from the top of the head to between the legs.
    /// The right half is its mirror (x -> 696 - x); together they form one closed, smooth contour.
    static let leftOutline: [CGPoint] = [
        // Head and neck
        (348, 40), (318, 47), (298, 68), (289, 100), (290, 138), (298, 166), (310, 186), (322, 200),
        (326, 214), (326, 230),
        // Shoulder, outer arm, hand, inner arm
        (314, 244), (290, 252), (258, 260), (236, 274), (222, 298), (208, 350), (194, 420), (182, 494),
        (171, 556), (162, 598), (148, 626), (140, 658), (146, 690), (164, 704), (182, 696), (190, 668),
        (194, 634), (200, 596), (210, 536), (222, 470), (236, 404), (250, 352), (262, 326),
        // Torso side, hip, outer leg, foot, inner leg
        (272, 346), (280, 400), (284, 456), (282, 510), (270, 566), (248, 620), (234, 680), (232, 760),
        (240, 860), (250, 950), (250, 1030), (250, 1110), (260, 1190), (264, 1232), (252, 1264),
        (254, 1292), (280, 1304), (308, 1298), (318, 1274), (316, 1236), (320, 1160), (326, 1070),
        (328, 990), (332, 900), (338, 800), (341, 740), (348, 722),
    ].map { CGPoint(x: $0.0, y: $0.1) }

    static let heart = CGPoint(x: 372, y: 352)

    /// Glow ellipses per region (center, radii), mirrored for paired parts.
    /// Throat, chest and stomach positions follow BodyMap.dc.html.
    static let regions: [BodyRegion: [CGRect]] = [
        .head: [ellipse(348, 92, 54, 44)],
        .face: [ellipse(348, 160, 42, 30)],
        .throat: [ellipse(348, 214, 26, 20)],
        .shoulders: [ellipse(262, 268, 42, 28), ellipse(434, 268, 42, 28)],
        .chest: [ellipse(348, 370, 78, 46)],
        .stomach: [ellipse(348, 470, 58, 36)],
        .belly: [ellipse(348, 565, 60, 36)],
        .pelvis: [ellipse(348, 670, 82, 44)],
        .arms: pair(212, 440, 30, 140),
        .hands: pair(165, 652, 30, 46),
        .legs: [ellipse(290, 820, 50, 110), ellipse(406, 820, 50, 110),
                ellipse(284, 1110, 34, 95), ellipse(412, 1110, 34, 95)],
        .knees: pair(286, 965, 36, 38),
        .feet: pair(278, 1265, 34, 40),
        .neckBack: [ellipse(348, 214, 28, 24)],
        .upperBack: [ellipse(348, 345, 86, 62)],
        .lowerBack: [ellipse(348, 545, 62, 42)],
        .hips: [ellipse(348, 680, 88, 50)],
        // Chip only; not hit-tested. Glows over the whole figure.
        .wholeBody: [ellipse(348, 670, 230, 640)],
    ]

    /// Back view details: spine, shoulder blades and seat line as short soft curves well inside the outline.
    static let backDetails: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 348, y: 262))
        p.addCurve(to: CGPoint(x: 348, y: 560), control1: CGPoint(x: 346, y: 360), control2: CGPoint(x: 350, y: 460))
        for sign: CGFloat in [-1, 1] {
            p.move(to: CGPoint(x: 348 + sign * 30, y: 304))
            p.addCurve(to: CGPoint(x: 348 + sign * 46, y: 392),
                       control1: CGPoint(x: 348 + sign * 56, y: 314), control2: CGPoint(x: 348 + sign * 62, y: 360))
        }
        p.move(to: CGPoint(x: 348, y: 662))
        p.addCurve(to: CGPoint(x: 348, y: 708), control1: CGPoint(x: 347, y: 678), control2: CGPoint(x: 348, y: 694))
        return p
    }()

    static func pair(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> [CGRect] {
        [ellipse(cx, cy, rx, ry), ellipse(696 - cx, cy, rx, ry)]
    }

    static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGRect {
        CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)
    }

    /// Nearest region to a point in SVG space, within a generous margin for 44 pt targets.
    static func region(at p: CGPoint, side: BodySide) -> BodyRegion? {
        var best: (BodyRegion, CGFloat)?
        for (region, rects) in regions where region != .wholeBody && region.sides.contains(side) {
            for r in rects {
                let dx = (p.x - r.midX) / (r.width / 2 + 14)
                let dy = (p.y - r.midY) / (r.height / 2 + 14)
                let d = dx * dx + dy * dy
                if d <= 1, d < (best?.1 ?? .infinity) { best = (region, d) }
            }
        }
        return best?.0
    }

    /// One closed contour through the outline points, as a Catmull-Rom spline turned into cubic Béziers.
    static let silhouette: Path = {
        let left = leftOutline
        let right = left.dropFirst().dropLast().reversed().map { CGPoint(x: 696 - $0.x, y: $0.y) }
        let pts = left + right
        let n = pts.count
        var p = Path()
        p.move(to: pts[0])
        for i in 0..<n {
            let p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n]
            p.addCurve(to: p2,
                       control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                       control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        p.closeSubpath()
        return p
    }()
}

/// The figure with glow on selected regions and a pulse ring at the heart (front only).
struct BodyFigureView: View {
    var selected: Set<BodyRegion> = []
    var side: BodySide = .front
    var pulse = true
    var onTap: ((BodyRegion) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = false

    private func glowRects(_ t: CGAffineTransform) -> [CGRect] {
        selected.filter { $0.sides.contains(side) }
            .flatMap { FigureGeometry.regions[$0] ?? [] }
            .map { $0.applying(t) }
    }

    var body: some View {
        GeometryReader { geo in
            let vb = FigureGeometry.viewBox
            let scale = min(geo.size.width / vb.width, geo.size.height / vb.height)
            let offset = CGPoint(x: (geo.size.width - vb.width * scale) / 2 - vb.minX * scale,
                                 y: (geo.size.height - vb.height * scale) / 2 - vb.minY * scale)
            let t = CGAffineTransform(translationX: offset.x, y: offset.y).scaledBy(x: scale, y: scale)
            let shape = FigureGeometry.silhouette.applying(t)

            ZStack {
                // One closed outline: fill, details and glows, then a single stroke on top. No seams to hide.
                shape.fill(LinearGradient(colors: [Palette.figureTop, Palette.figureBottom], startPoint: .top, endPoint: .bottom))

                if side == .back {
                    FigureGeometry.backDetails.applying(t)
                        .stroke(Palette.figureStroke.opacity(0.45), style: StrokeStyle(lineWidth: max(1, 2.5 * scale), lineCap: .round))
                }

                ZStack {
                    ForEach(Array(glowRects(t).enumerated()), id: \.offset) { _, rr in
                        GlowSpot(rect: rr, maxBlur: 28 * scale)
                    }
                }
                .clipShape(shape)

                shape.stroke(Palette.figureStroke, style: StrokeStyle(lineWidth: max(1.5, 4 * scale), lineCap: .round, lineJoin: .round))

                if pulse && side == .front {
                    let h = FigureGeometry.heart.applying(t)
                    ZStack {
                        Circle().stroke(Palette.action.opacity(0.2), lineWidth: 2).frame(width: 80 * scale, height: 80 * scale)
                            .scaleEffect(beat ? 1.15 : 0.95)
                        Circle().stroke(Palette.action.opacity(0.45), lineWidth: 2).frame(width: 48 * scale, height: 48 * scale)
                        Circle().fill(Palette.action).frame(width: max(4, 18 * scale), height: max(4, 18 * scale))
                    }
                    .position(h)
                    .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard let onTap else { return }
                let p = location.applying(t.inverted())
                if let region = FigureGeometry.region(at: p, side: side) { onTap(region) }
            }
        }
        .aspectRatio(FigureGeometry.viewBox.width / FigureGeometry.viewBox.height, contentMode: .fit)
        .onAppear {
            guard pulse, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { beat = true }
        }
    }
}

/// One soft glow. Small regions (throat, back of neck) get less blur so they stay visible.
struct GlowSpot: View {
    let rect: CGRect
    let maxBlur: CGFloat

    var body: some View {
        Ellipse()
            .fill(Palette.pink.opacity(0.7))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .blur(radius: min(maxBlur, min(rect.width, rect.height) * 0.3))
    }
}

/// Where do you feel it? (screen 08). The back view is our own derivation; the mockups show only the front.
struct BodyMapView: View {
    let draft: CaptureDraft
    /// From Now: saves the entry right here (owner, 2026-11-02: picks waited unsaved on Now and
    /// were lost). Listen passes nil and keeps its own Keep button.
    var onSave: ((Entry) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var side: BodySide = .front
    @State private var selected: Set<BodyRegion> = []
    @State private var sensations: [String] = []
    @State private var own = ""
    @State private var typingOwn = false
    @State private var showMore = false

    private func toggle(_ s: String) {
        if let i = sensations.firstIndex(of: s) { sensations.remove(at: i) } else { sensations.append(s) }
    }

    /// Copies what is picked into the entry being written. Safe to call often.
    private func commit() {
        let regions = ordered.map(\.rawValue)
        if draft.regions != regions { draft.regions = regions }
        if draft.sensations != sensations { draft.sensations = sensations }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Where do you feel it?")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Palette.ink)
                    .minimumScaleFactor(0.8)
                Text("Tap as many places as you like.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 24)

            Picker("Side", selection: $side) {
                Text("Front").tag(BodySide.front)
                Text("Back").tag(BodySide.back)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)

            BodyFigureView(selected: selected, side: side) { region in
                if selected.contains(region) { selected.remove(region) } else { selected.insert(region) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 8)
            .background(RadialGradient(colors: [Palette.tint1, .clear], center: .center, startRadius: 0, endRadius: 220))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(side == .front ? "Body figure, front" : "Body figure, back")

            // VoiceOver and Switch Control path to the same regions.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BodyRegion.regions(on: side), id: \.self) { region in
                        Chip(title: region.label, selected: selected.contains(region)) {
                            if selected.contains(region) { selected.remove(region) } else { selected.insert(region) }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }

            Text(selected.isEmpty ? "What does it feel like?" : "\(ordered.map(\.label).joined(separator: ", ")). What does it feel like?")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Picked words that are not in the short list come first, so they stay visible.
                    ForEach(sensations.filter { !Sensations.common.contains($0) } + Sensations.common, id: \.self) { s in
                        Chip(title: s, selected: sensations.contains(s)) { toggle(s) }
                    }
                    Chip(title: "More words") { showMore = true }
                    Chip(title: "My own", selected: typingOwn) { typingOwn.toggle() }
                }
                .padding(.horizontal, 24)
            }

            if typingOwn {
                TextField("Your word", text: $own)
                    .padding(14)
                    .card(radius: 16)
                    .padding(.horizontal, 24)
                    .submitLabel(.done)
                    .onSubmit {
                        let w = own.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !w.isEmpty, !sensations.contains(w) { sensations.append(w) }
                        own = ""
                        typingOwn = false
                    }
            }

            if let onSave {
                Button("Save") {
                    commit()
                    onSave(draft.save(in: context))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selected.isEmpty && sensations.isEmpty)
                .padding(.horizontal, 24)
                Text("Saves now, with anything you wrote on Now. Back keeps it to add more first.")
                    .font(.caption).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.horizontal, 24)
            }
        }
        .padding(.bottom, 12)
        .background(Palette.surface.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    commit()
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showMore) {
            SensationSheet(sensations: $sensations)
        }
        // Owner, 2026-11-02: places picked here were lost when she went back with the back arrow
        // or a swipe instead of Done. Every tap now goes straight into the entry being written.
        .onChange(of: selected) { commit() }
        .onChange(of: sensations) { commit() }
        .onDisappear { commit() }
        .onAppear {
            selected = Set(draft.regions.compactMap(BodyRegion.init(rawValue:)))
            sensations = draft.sensations
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-openBodyMore") { sensations = ["Fluttery", "Tight"]; showMore = true }
            if ProcessInfo.processInfo.arguments.contains("-bodyAll") { selected = [.face, .shoulders, .belly, .hands, .knees, .feet] }
            if ProcessInfo.processInfo.arguments.contains("-bodyBack") { side = .back; selected = [.neckBack, .lowerBack, .shoulders, .hips] }
            #endif
        }
    }

    private var ordered: [BodyRegion] { BodyRegion.allCases.filter(selected.contains) }
}

/// Every sensation word, grouped. Tap as many as fit.
struct SensationSheet: View {
    @Binding var sensations: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Sensations.groups) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.name)
                                .font(.headline)
                                .foregroundStyle(Palette.ink)
                                .accessibilityAddTraits(.isHeader)
                            FlowLayout(spacing: 8) {
                                ForEach(group.words, id: \.self) { w in
                                    Chip(title: w, selected: sensations.contains(w)) {
                                        if let i = sensations.firstIndex(of: w) { sensations.remove(at: i) } else { sensations.append(w) }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Palette.surface.ignoresSafeArea())
            .navigationTitle("What does it feel like?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
