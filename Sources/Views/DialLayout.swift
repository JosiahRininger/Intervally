//
//  DialLayout.swift
//  Intervally
//

import CoreGraphics

/// The one geometry every dial screen shares — Setup, Run and Summary — measured from the
/// full display (both safe areas ignored) so the ring, not the chrome, decides the layout.
///
/// Sharing it is the point. The ring sits in the same place at the same size on all three
/// screens, so Start reads as the ring changing state rather than as a new screen arriving,
/// and the bottom control row (Start, End + Pause, Done) never moves under the thumb.
///
/// Sizing from the height left under the toolbar gave an 87pt ring on a 46mm watch. This
/// gives ~140pt there and ~102pt on 40mm: the ring extends up beneath the corner toolbar
/// glyphs (a circle's corners are empty, so nothing collides), the system time sits just
/// above its top arc, and the controls sit low, where the display's corner radius leaves
/// room for circles and a centred capsule but not for a full-width bar.
struct DialLayout {
    let diameter: CGFloat
    let stroke: CGFloat
    /// The square that fits inside the ring's stroke, for its content.
    let interior: CGFloat
    /// Height of the bottom controls: the End / Pause circles, and the Start / Done capsule.
    let control: CGFloat
    /// Width of a centred Start / Done capsule.
    let capsuleWidth: CGFloat
    /// Top of the ring, from the top of the display.
    let ringTop: CGFloat
    let bottomMargin: CGFloat = 10
    /// Between the ring and the control row.
    let gap: CGFloat = 12

    init(screen: CGSize) {
        // The status-bar clock scales with the display; ~14.5% of the height clears it.
        // The Ultras set their clock ~3pt lower, which left the arc grazing its digits.
        ringTop = (screen.height * 0.145).rounded() + (screen.height >= 250 ? 3 : 0)
        control = min(52, max(44, (screen.height * 0.2).rounded()))
        capsuleWidth = (screen.width * 0.6).rounded()
        diameter = min(screen.width - 16, screen.height - ringTop - gap - control - bottomMargin)
        stroke = ProgressRing.strokeWidth(for: diameter)
        interior = diameter - 2 * stroke - 8
    }

    /// The widest a line of text can be at `offset` points above or below the ring's
    /// centre without touching the stroke — what a label near the top of the interior,
    /// or a footer near its bottom, actually has to work with.
    func chord(atOffset offset: CGFloat) -> CGFloat {
        let radius = diameter / 2 - stroke - 2
        let d = min(abs(offset), radius)
        return 2 * (radius * radius - d * d).squareRoot()
    }
}
