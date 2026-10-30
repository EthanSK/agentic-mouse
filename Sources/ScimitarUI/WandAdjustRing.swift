import ScimitarKit
import SwiftUI

/// Presentation rules for the wand's wheel-adjustment outline, kept pure so
/// reduce motion, stepping and geometry stay testable without rendering.
///
/// Navigation draws a solid white liquid outline that stretches toward the
/// next card. An armed wheel card is a dashed white ring. While that card is
/// being adjusted it becomes a finer ratchet ring in the card's own action
/// colour: it stretches only vertically toward the next detent, its notches
/// advance one notch for every detent actually sent, and each sent detent
/// releases one short ripple toward the edge it was sent from. It shows input
/// attempts only, never an application value.
enum WandAdjustRingStyle {
    static let dash: [CGFloat] = [5, 4]
    static let dashPeriod: CGFloat = 9
    static let lineWidth: CGFloat = 4.25
    static let rippleTravel: CGFloat = 6
    static let rippleGrowth: CGFloat = 0.06

    /// One notch per sent detent: up advances, down rewinds.
    static func dashPhase(netSteps: Int) -> CGFloat {
        CGFloat(netSteps) * dashPeriod
    }

    /// Ripples lean toward the top edge for an up detent and the bottom edge
    /// for a down detent.
    static func rippleOffset(lastStepWasUp: Bool?) -> CGFloat {
        switch lastStepWasUp {
        case .some(true): return -rippleTravel
        case .some(false): return rippleTravel
        case .none: return 0
        }
    }

    /// Every animation is a one-shot response to a state change; nothing
    /// repeats while the card is idle. Reduce Motion keeps the same discrete
    /// information (notch position and vertical stretch) without movement.
    static func notchAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.72)
    }

    static func stretchAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .linear(duration: 0.03)
    }

    static func rippleAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.34)
    }

    static func showsRipple(_ adjustment: ModeHUDWheelAdjustment, reduceMotion: Bool) -> Bool {
        !reduceMotion && adjustment.sentSteps > 0
    }
}

/// Ethan: "make the dotted outline ... like moving dynamics, like cool, like
/// a snake around it". An armed card keeps its dotted ring, and the dots
/// travel clockwise around it like marching ants. Hover stays solid and the
/// adjustment ratchet keeps its own detent notches. Both wand outline views
/// (wheel and grid) read this one policy.
///
/// The phase is a pure function of time, so every outline marches in step
/// and Reduce Motion shows the same dots standing still. Nothing ticks
/// unless an armed card is actually showing its dots.
enum WandArmedOutlineStyle {
    static let dash: [CGFloat] = ModeHUDPointerFocusMetrics.armedDash
    static var dashPeriod: CGFloat { dash.reduce(0, +) }
    /// Points per second the dots travel along the outline.
    static let speed: CGFloat = 28
    /// Caps redraws on high-refresh displays; the motion is a gentle march.
    static let frameInterval: TimeInterval = 1.0 / 60

    /// Armed and waiting: the only state whose dots move.
    static func marches(_ focus: ModeHUDPointerFocus, reduceMotion: Bool) -> Bool {
        focus.isArmed && focus.adjustment == nil && !reduceMotion
    }

    static func schedule(for focus: ModeHUDPointerFocus, reduceMotion: Bool) -> AnimationTimelineSchedule {
        .animation(minimumInterval: frameInterval, paused: !marches(focus, reduceMotion: reduceMotion))
    }

    /// Dash phase at `date`, in (−period, 0]. Outlines are drawn clockwise,
    /// and a falling phase moves the dots forward along the path, so they
    /// travel clockwise. Reduce Motion keeps them still.
    static func dashPhase(at date: Date, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion, dashPeriod > 0, speed > 0 else { return 0 }
        let cycle = Double(dashPeriod / speed)
        var elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        if elapsed < 0 { elapsed += cycle }
        return -CGFloat(elapsed) * speed
    }
}

struct WandAdjustRing: View {
    let adjustment: ModeHUDWheelAdjustment
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            WandLiquidOutline(pullX: 0, pullY: adjustment.pull)
                .stroke(
                    LinearGradient(colors: [accent, .white, accent], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(
                        lineWidth: WandAdjustRingStyle.lineWidth,
                        lineCap: .round,
                        dash: WandAdjustRingStyle.dash,
                        dashPhase: WandAdjustRingStyle.dashPhase(netSteps: adjustment.netSteps)
                    )
                )
                .animation(WandAdjustRingStyle.notchAnimation(reduceMotion: reduceMotion),
                           value: adjustment.netSteps)
                .animation(WandAdjustRingStyle.stretchAnimation(reduceMotion: reduceMotion),
                           value: adjustment.pull)

            if WandAdjustRingStyle.showsRipple(adjustment, reduceMotion: reduceMotion) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(accent, lineWidth: 2)
                    .id(adjustment.sentSteps)
                    .transition(.asymmetric(
                        insertion: .modifier(
                            active: WandAdjustRipple(phase: 0, offset: WandAdjustRingStyle.rippleOffset(lastStepWasUp: adjustment.lastStepWasUp)),
                            identity: WandAdjustRipple(phase: 1, offset: WandAdjustRingStyle.rippleOffset(lastStepWasUp: adjustment.lastStepWasUp))
                        ),
                        removal: .identity
                    ))
            }
        }
        .animation(WandAdjustRingStyle.rippleAnimation(reduceMotion: reduceMotion),
                   value: adjustment.sentSteps)
        .padding(-ModeHUDPointerFocusMetrics.outset)
        .shadow(color: accent.opacity(0.8), radius: 7)
        .allowsHitTesting(false)
    }
}

/// A sent detent's pulse: it starts on the ring and settles invisible, a
/// little larger and nudged toward the step's edge. Its resting state is
/// invisible, so a skipped or reduced-motion insertion shows nothing.
private struct WandAdjustRipple: ViewModifier {
    let phase: CGFloat
    let offset: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(1 + WandAdjustRingStyle.rippleGrowth * phase)
            .offset(y: offset * phase)
            .opacity(Double(1 - phase))
    }
}
