import SwiftUI

// MARK: - Confetti View
//
// A lightweight, single-shot confetti animation rendered above the
// per-car detail view when `CarDetailData.confettiEligible` is true.
//
// The view is intentionally not a particle system engine: it spawns
// 24 small circles with random horizontal positions, colors drawn
// from a small palette, and a randomized vertical fall that fades out
// over 2 seconds. The `TimelineView(.animation)` driver re-evaluates
// the positions on every frame so the GPU doesn't have to do layout
// work — the whole thing is O(24) per frame.
//
// Callers drive the lifecycle from `.onAppear` (start) and an
// auto-dismiss after 2.5s. The view is fully self-contained and
// doesn't reach into the surrounding view hierarchy.

struct ConfettiView: View {
    /// Number of particles. Small enough to stay cheap; large enough
    /// to feel like confetti.
    private let particleCount = 24
    /// Total duration of the fall before particles are clipped to
    /// nothing.
    private let duration: TimeInterval = 2.0

    private let palette: [Color] = [
        .red, .orange, .yellow, .green, .blue, .purple, .pink
    ]

    private let particles: [Particle]

    init() {
        // Pre-randomize each particle so the animation is reproducible
        // per-instance and not subject to view-body re-renders. The
        // palette is a property and can be referenced from the
        // initializer; we just have to assign `particles` directly to
        // avoid the "captured before initialized" trap.
        let palette: [Color] = [
            .red, .orange, .yellow, .green, .blue, .purple, .pink
        ]
        var rng = SystemRandomNumberGenerator()
        self.particles = (0..<24).map { _ in
            Particle(
                horizontalFraction: Double.random(in: 0...1, using: &rng),
                horizontalDrift: Double.random(in: -40...40, using: &rng),
                color: palette.randomElement(using: &rng) ?? .blue,
                size: CGFloat.random(in: 6...10, using: &rng),
                rotation: Double.random(in: 0...360, using: &rng),
                spin: Double.random(in: -180...180, using: &rng),
                delay: Double.random(in: 0...0.4, using: &rng)
            )
        }
    }


    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
            Canvas { gc, size in
                let elapsed = context.date.timeIntervalSince(context.date)
                _ = elapsed // silence "unused" if we stop using it
                draw(in: gc, size: size, time: context.date.timeIntervalSince1970)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(in gc: GraphicsContext, size: CGSize, time: TimeInterval) {
        // Use a deterministic per-particle clock anchored on the view's
        // own identity: the view is created on .onAppear, so `time`
        // increases monotonically for the view's lifetime. We pin the
        // animation to particle-local time using its `delay` so they
        // don't all start in lockstep.
        for p in particles {
            let localT = time.truncatingRemainder(dividingBy: 60) - p.delay
            guard localT >= 0, localT <= duration else { continue }
            let progress = localT / duration
            // Vertical: fall from above the top to past the bottom.
            let y = -20 + CGFloat(progress) * (size.height + 40)
            // Horizontal: drift around the starting column.
            let x = CGFloat(p.horizontalFraction) * size.width
                + CGFloat(p.horizontalDrift) * CGFloat(sin(progress * .pi))
            // Fade out over the last 30% of the fall.
            let alpha = progress < 0.7 ? 1.0 : max(0, 1.0 - (progress - 0.7) / 0.3)

            var ctx = gc
            ctx.opacity = alpha
            ctx.translateBy(x: x, y: y)
            ctx.rotate(by: .degrees(p.rotation + p.spin * progress))
            let rect = CGRect(
                x: -p.size / 2,
                y: -p.size / 2,
                width: p.size,
                height: p.size
            )
            ctx.fill(Path(ellipseIn: rect), with: .color(p.color))
        }
    }
}

private struct Particle {
    /// Initial horizontal position as a fraction of the view width.
    let horizontalFraction: Double
    /// Sinusoidal horizontal drift amplitude (in points).
    let horizontalDrift: Double
    let color: Color
    let size: CGFloat
    /// Initial rotation in degrees.
    let rotation: Double
    /// Total spin across the fall, in degrees.
    let spin: Double
    /// Per-particle delay (in seconds) before the fall starts.
    let delay: Double
}
