import UIKit
import SwiftUI

/// Opening (design: Opening.dc.html). Shown while AiHeart gets ready: the heart with soft
/// pulse rings, the wordmark, and the privacy line. Still under Reduce Motion.
struct OpeningView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Palette.surface.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                RippleHeart(reduceMotion: reduceMotion)
                .frame(height: 340)
                .accessibilityHidden(true)
                Text("AiHeart")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Palette.action)
                    .padding(.top, 30)
                Spacer()
                Text("Everything stays on your devices.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .padding(.bottom, 56)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AiHeart is opening. Everything stays on your devices.")
    }
}

/// Rings that grow out of the heart and fade, and a heart that swells once per ripple.
/// Runs in Core Animation, off the main thread, so it stays smooth while the first screens
/// are built. Still when Reduce Motion is on.
struct RippleHeart: UIViewRepresentable {
    let reduceMotion: Bool

    func makeUIView(context: Context) -> RippleHeartView {
        let v = RippleHeartView(reduceMotion: reduceMotion)
        return v
    }

    func updateUIView(_ uiView: RippleHeartView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: RippleHeartView, context: Context) -> CGSize? {
        CGSize(width: 340, height: 340)
    }
}

final class RippleHeartView: UIView {
    private let reduceMotion: Bool
    private let period: CFTimeInterval = 2.4
    private var built = false

    init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        super.init(frame: CGRect(x: 0, y: 0, width: 340, height: 340))
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !built, bounds.width > 0 else { return }
        built = true
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let pink = UIColor(Palette.pink)

        // Rings: start at radius 80, grow to 170, fade out. Three, evenly staggered.
        let base: CGFloat = 170
        for i in 0..<3 {
            let ring = CAShapeLayer()
            ring.path = UIBezierPath(ovalIn: CGRect(x: -base, y: -base, width: base * 2, height: base * 2)).cgPath
            ring.position = c
            ring.fillColor = UIColor.clear.cgColor
            ring.strokeColor = pink.cgColor
            ring.lineWidth = 2
            layer.addSublayer(ring)
            if reduceMotion {
                let r: [CGFloat] = [105, 135, 165]
                ring.transform = CATransform3DMakeScale(r[i] / base, r[i] / base, 1)
                ring.opacity = [0.55, 0.3, 0.14][i]
                continue
            }
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 80 / base
            scale.toValue = 1
            scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.55
            fade.toValue = 0
            fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
            // Keep the line width steady while the ring grows.
            let width = CABasicAnimation(keyPath: "lineWidth")
            width.fromValue = 2 * base / 80
            width.toValue = 2
            width.timingFunction = scale.timingFunction
            let group = CAAnimationGroup()
            group.animations = [scale, fade, width]
            group.duration = period
            group.repeatCount = .infinity
            group.beginTime = CACurrentMediaTime() - Double(i) * period / 3
            group.isRemovedOnCompletion = false
            ring.opacity = 0
            ring.add(group, forKey: "ripple")
        }

        // Soft glow behind the heart.
        let glow = CAGradientLayer()
        glow.type = .radial
        glow.colors = [UIColor.white.cgColor, UIColor(Palette.tint1).cgColor, UIColor(Palette.tint1).withAlphaComponent(0).cgColor]
        glow.locations = [0, 0.5, 1]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.frame = CGRect(x: c.x - 75, y: c.y - 75, width: 150, height: 150)
        layer.addSublayer(glow)

        // Heart.
        let config = UIImage.SymbolConfiguration(pointSize: 64)
        let heart = UIImageView(image: UIImage(systemName: "heart.fill", withConfiguration: config))
        heart.tintColor = UIColor(Palette.action)
        heart.sizeToFit()
        heart.center = c
        addSubview(heart)
        if !reduceMotion {
            let beat = CAKeyframeAnimation(keyPath: "transform.scale")
            beat.values = [1, 1.06, 1, 1]
            beat.keyTimes = [0, 0.18, 0.45, 1]
            beat.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .linear)]
            beat.duration = period
            beat.repeatCount = .infinity
            beat.isRemovedOnCompletion = false
            heart.layer.add(beat, forKey: "beat")
        }
    }
}

/// Shimmering placeholder block (design: Skeleton.dc.html).
struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var radius: CGFloat = 7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Palette.skeleton)
            .overlay {
                if !reduceMotion {
                    GeometryReader { g in
                        LinearGradient(colors: [.clear, Palette.skeletonHighlight, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: g.size.width * 0.6)
                            .offset(x: phase * g.size.width)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: radius))
                }
            }
            .frame(width: width, height: height)
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1.4 }
            }
    }
}

/// Insights while data is still arriving.
struct InsightsSkeleton: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity)
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 10) { tile; tile }
            }
            VStack(alignment: .leading, spacing: 10) {
                SkeletonBar(width: 90, height: 13)
                SkeletonBar(height: 30, radius: 10)
                SkeletonBar(height: 14)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            HStack(spacing: 16) {
                Circle().stroke(Palette.skeleton, lineWidth: 10).frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 10) {
                    SkeletonBar(width: 150, height: 16)
                    SkeletonBar(width: 190, height: 12)
                    SkeletonBar(width: 100, height: 12)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBar(width: 50, height: 12)
            SkeletonBar(width: 90, height: 22, radius: 8)
            SkeletonBar(height: 30, radius: 10)
            SkeletonBar(width: 80, height: 11)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
