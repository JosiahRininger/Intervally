//
//  Theme.swift
//  Intervally
//

import SwiftUI

/// Classic's palette and the app's type, typed rather than looked up by string.
///
/// Colour is state here: amber for the lead-in, ember for the warmup, blue for work, green
/// for rest, lavender for the cooldown. One ring, one tinted control and one label carry it;
/// everything else is monochrome on black. These are Intervally's own hues — deliberately
/// not the red / lime / cyan trio of Apple's Activity rings, and never shown as concentric
/// rings.
///
/// These are Classic's colours, the free look. Views read the theme the user chose from the
/// environment (`\.palette`, see `Palette`); these statics stay for code that has no
/// environment and for Classic itself.
enum Theme {
    /// Amber — the lead-in.
    static let prepare = Color(.displayP3, red: 1.000, green: 0.769, blue: 0.231)
    /// Ember — the warmup. Warmer and deeper than the lead-in's amber, so the two read as
    /// separate phases when one follows the other. Black text 8.6:1.
    static let warmup = Color(.displayP3, red: 1.000, green: 0.502, blue: 0.200)
    /// Sky blue — work, and the brand colour.
    static let work = Color(.displayP3, red: 0.153, green: 0.749, blue: 1.000)
    /// Emerald — rest. Kept well away from the work hue; those two must be told apart mid-set.
    static let rest = Color(.displayP3, red: 0.298, green: 0.851, blue: 0.541)
    /// Lavender — the cooldown. Away from both work and rest, because it follows the last
    /// work interval directly. Black text 8.5:1.
    static let cooldown = Color(.displayP3, red: 0.706, green: 0.565, blue: 1.000)

    /// Deeper variants, used only where the display is dimmed (Always-On) and for the
    /// bottom of the completion gradient — never brighter than the active colour.
    static let prepareDimmed = Color(.displayP3, red: 0.851, green: 0.541, blue: 0.086)
    static let warmupDimmed = Color(.displayP3, red: 0.851, green: 0.361, blue: 0.078)
    static let workDimmed = Color(.sRGB, red: 0.035, green: 0.631, blue: 0.871)
    static let restDimmed = Color(.displayP3, red: 0.086, green: 0.612, blue: 0.396)
    static let cooldownDimmed = Color(.displayP3, red: 0.545, green: 0.420, blue: 0.902)
    static let brandDeep = workDimmed

    /// Label colour on any phase-tinted capsule. White on these hues measured under 3:1;
    /// black measures 9.9:1 on work and at least 5.4:1 on every dimmed variant.
    static let onTint = Color.black

    static func light(for kind: IntervalPhase.Kind) -> Color {
        switch kind {
        case .prepare: prepare
        case .warmup: warmup
        case .work: work
        case .rest: rest
        case .cooldown: cooldown
        }
    }

    static func dimmed(for kind: IntervalPhase.Kind) -> Color {
        switch kind {
        case .prepare: prepareDimmed
        case .warmup: warmupDimmed
        case .work: workDimmed
        case .rest: restDimmed
        case .cooldown: cooldownDimmed
        }
    }

    /// The unfilled part of a ring: the phase colour, faint.
    static func track(for kind: IntervalPhase.Kind) -> Color {
        light(for: kind).opacity(0.20)
    }

    // Older names, kept so call sites migrate screen by screen.
    static let workLight = work
    static let workDark = workDimmed
    static let restLight = rest
    static let restDark = restDimmed
    static let prepareLight = prepare
    static let prepareDark = prepareDimmed
    static func dark(for kind: IntervalPhase.Kind) -> Color { dimmed(for: kind) }
}

// MARK: - Palettes

/// Every colour a screen draws with, for one theme on one device. Read from the environment
/// (`@Environment(\.palette)`), which each app's root sets from the effective theme
/// (`AppTheme.effective`), so a change of theme redraws every screen at once.
///
/// Four kinds of colour:
/// - **Fills** carry a phase as area: rings, the boundary flash, the one tinted control,
///   chart bars. On the watch they are also its phase-coloured text, on black.
/// - **Dimmed** fills, for Always-On and the bottom of the completion gradient. Never
///   brighter than the fill.
/// - **Ink** is a phase as text or a glyph on this device's canvas and cards: the fill where
///   the canvas is black, a deeper shade on Pastel's light iPhone canvas.
/// - **Surfaces** (`canvas`, `card`, `neutral`, `colorScheme`, `glassTint`) are the iPhone's.
///   The watch keeps its black screen in every theme, as Apple's watchOS guidance asks of a
///   workout app (glare and battery mid-workout), and reads the phase colours and, for its
///   titles, the `accent`.
///
/// Every pairing that carries text is measured in WCAG 2 contrast and pinned by
/// `PaletteContrastTests`, so a colour can't drift below what was measured.
struct Palette: Equatable, Sendable {
    let theme: AppTheme

    let prepare: Color
    let warmup: Color
    let work: Color
    let rest: Color
    let cooldown: Color

    let prepareDimmed: Color
    let warmupDimmed: Color
    let workDimmed: Color
    let restDimmed: Color
    let cooldownDimmed: Color

    let prepareInk: Color
    let warmupInk: Color
    let workInk: Color
    let restInk: Color
    let cooldownInk: Color

    /// The label on any phase-tinted capsule, and on the complication's tinted face.
    let onTint: Color

    /// Behind every iPhone screen, under its list or scroll view too.
    let canvas: Color
    /// A tile or card on the canvas.
    let card: Color
    /// What Classic draws in white because it means no phase: the rounds in a rhythm line,
    /// its separators, History's completion ring, chart grid lines.
    let neutral: Color
    /// The iPhone's appearance. The app is Dark by Info.plist; Pastel asks for Light at the
    /// root, so system bars, glass, lists and text adapt with it.
    let colorScheme: ColorScheme
    /// The tint of system controls that take the app's accent: links, toggles, the selected
    /// tab, a sheet's Done. Nil keeps the asset catalog's AccentColor, Classic's work blue.
    let accent: Color?
    /// iPhone bar buttons and neutral glass controls. They stay in the label colour, grey
    /// glass as in Classic, rather than take Pastel's accent from the root: colour is kept
    /// for phases and the one tinted control. Nil where the root sets no tint to undo.
    let glassTint: Color?

    func fill(for kind: IntervalPhase.Kind) -> Color {
        switch kind {
        case .prepare: prepare
        case .warmup: warmup
        case .work: work
        case .rest: rest
        case .cooldown: cooldown
        }
    }

    func dimmed(for kind: IntervalPhase.Kind) -> Color {
        switch kind {
        case .prepare: prepareDimmed
        case .warmup: warmupDimmed
        case .work: workDimmed
        case .rest: restDimmed
        case .cooldown: cooldownDimmed
        }
    }

    func ink(for kind: IntervalPhase.Kind) -> Color {
        switch kind {
        case .prepare: prepareInk
        case .warmup: warmupInk
        case .work: workInk
        case .rest: restInk
        case .cooldown: cooldownInk
        }
    }

    /// The unfilled part of a ring: the phase colour, faint.
    func track(for kind: IntervalPhase.Kind) -> Color {
        fill(for: kind).opacity(0.20)
    }

    /// The brand colour is work's, as in the icon and the completion screen.
    var brand: Color { work }
    var brandDeep: Color { workDimmed }

    /// The palette for `theme` on this device: Pastel's surfaces differ between the iPhone's
    /// light canvas and the watch's black one.
    static func of(_ theme: AppTheme) -> Palette {
        switch theme {
        case .classic: .classic
        #if os(watchOS)
        case .pastel: .pastelWatch
        #else
        case .pastel: .pastelPhone
        #endif
        }
    }

    /// The free look, on both devices: exactly `Theme`'s colours on black.
    static let classic = Palette(
        theme: .classic,
        prepare: Theme.prepare, warmup: Theme.warmup, work: Theme.work, rest: Theme.rest, cooldown: Theme.cooldown,
        prepareDimmed: Theme.prepareDimmed, warmupDimmed: Theme.warmupDimmed, workDimmed: Theme.workDimmed,
        restDimmed: Theme.restDimmed, cooldownDimmed: Theme.cooldownDimmed,
        // On black, phase text is the fill: 8.5:1 (cooldown) to 13.3:1 (lead-in), and at
        // least 7.1:1 on a card (white at 10% on black, #1A1A1A).
        prepareInk: Theme.prepare, warmupInk: Theme.warmup, workInk: Theme.work, restInk: Theme.rest,
        cooldownInk: Theme.cooldown,
        onTint: Theme.onTint,
        canvas: .black,
        card: .white.opacity(0.10),
        neutral: .white,
        colorScheme: .dark,
        accent: nil,
        glassTint: nil
    )

    // Pastel, an Intervally Pro theme: pink where Classic is blue, and soft versions of the
    // other phase colours. sRGB, each tier tuned to the ground it is drawn on. Contrast is
    // WCAG 2 relative luminance; "apart" is the smallest CIELAB difference to the phase it
    // borders, across normal vision and simulated protanopia, deuteranopia and tritanopia
    // (Machado 2009, full severity).
    //
    //   watch fill (on black)          dimmed (always-on)     iPhone fill    iPhone ink (text)
    //   prepare  #FFF0A6 lemon  18.3:1  #D9C25E 11.8:1          #E8D84A        #7A5A00  5.5:1 on card
    //   warmup   #FFB45A apricot 11.9:1 #E08A30  7.8:1          #FF8A3D        #A3460A  5.3:1
    //   work     #FF7490 rose    8.2:1  #E04A6E  5.4:1          #F5527A 3.1:1  #B81E48  5.5:1
    //   rest     #B9E7FA sky    15.9:1  #5FB0DE  8.8:1          #5CB8EC        #16628F  5.7:1
    //   cooldown #C9AEFF lilac  11.0:1  #9C7FE8  6.6:1          #A58BF5        #6646D0  5.4:1
    //
    // On the watch, where a glance mid-set has to tell phases apart, work and rest are 33
    // apart at worst (the first draft's pink and mint fell to 12 for deuteranopes; Classic's
    // blue and green are 71), and every border pair is at least 24. Black on the work fill
    // (onTint, the completion screen and the complication's tinted face) is 8.2:1, and at
    // least 5.4:1 on every dimmed variant. The iPhone's fills are deeper, for rings and
    // charts on a light canvas (work clears 3:1 there); its inks carry phase text at 5:1 or
    // better on a card. Canvas #FFF7FA, card #FFE9F0.

    /// Pastel on the watch: the phase colours on the watch's black screen. Ink is the fill,
    /// as in Classic.
    static let pastelWatch = Palette(
        theme: .pastel,
        prepare: Pastel.prepare, warmup: Pastel.warmup, work: Pastel.work, rest: Pastel.rest, cooldown: Pastel.cooldown,
        prepareDimmed: Pastel.prepareDimmed, warmupDimmed: Pastel.warmupDimmed, workDimmed: Pastel.workDimmed,
        restDimmed: Pastel.restDimmed, cooldownDimmed: Pastel.cooldownDimmed,
        prepareInk: Pastel.prepare, warmupInk: Pastel.warmup, workInk: Pastel.work, restInk: Pastel.rest,
        cooldownInk: Pastel.cooldown,
        onTint: .black,
        canvas: .black,
        card: .white.opacity(0.10),
        neutral: .white,
        colorScheme: .dark,
        // Never set at the watch's root, where a tint fills every glass button: only the
        // titles that should wear it take it (`accentTitle()`).
        accent: Pastel.work,
        glassTint: nil
    )

    /// Pastel on iPhone: a light appearance, warm white canvas and pale pink cards, with
    /// deeper inks for phase-coloured text.
    static let pastelPhone = Palette(
        theme: .pastel,
        prepare: Pastel.phonePrepare, warmup: Pastel.phoneWarmup, work: Pastel.phoneWork, rest: Pastel.phoneRest,
        cooldown: Pastel.phoneCooldown,
        prepareDimmed: Pastel.prepareDimmed, warmupDimmed: Pastel.warmupDimmed, workDimmed: Pastel.workDimmed,
        restDimmed: Pastel.restDimmed, cooldownDimmed: Pastel.cooldownDimmed,
        prepareInk: Pastel.prepareInk, warmupInk: Pastel.warmupInk, workInk: Pastel.workInk, restInk: Pastel.restInk,
        cooldownInk: Pastel.cooldownInk,
        onTint: .black,
        canvas: Pastel.canvas,
        card: Pastel.card,
        neutral: Pastel.neutral,
        colorScheme: .light,
        accent: Pastel.workInk,
        glassTint: .primary
    )
}

/// Pastel's colours, named once for both of its palettes.
private enum Pastel {
    // The watch: on black.
    static let prepare = Color(hex: 0xFFF0A6)
    static let warmup = Color(hex: 0xFFB45A)
    static let work = Color(hex: 0xFF7490)
    static let rest = Color(hex: 0xB9E7FA)
    static let cooldown = Color(hex: 0xC9AEFF)

    static let prepareDimmed = Color(hex: 0xD9C25E)
    static let warmupDimmed = Color(hex: 0xE08A30)
    static let workDimmed = Color(hex: 0xE04A6E)
    static let restDimmed = Color(hex: 0x5FB0DE)
    static let cooldownDimmed = Color(hex: 0x9C7FE8)

    // The iPhone: deeper fills for rings and charts on the light canvas, and inks for text.
    static let phonePrepare = Color(hex: 0xE8D84A)
    static let phoneWarmup = Color(hex: 0xFF8A3D)
    static let phoneWork = Color(hex: 0xF5527A)
    static let phoneRest = Color(hex: 0x5CB8EC)
    static let phoneCooldown = Color(hex: 0xA58BF5)

    static let prepareInk = Color(hex: 0x7A5A00)
    static let warmupInk = Color(hex: 0xA3460A)
    static let workInk = Color(hex: 0xB81E48)
    static let restInk = Color(hex: 0x16628F)
    static let cooldownInk = Color(hex: 0x6646D0)

    static let canvas = Color(hex: 0xFFF7FA)
    static let card = Color(hex: 0xFFE9F0)
    static let neutral = Color(hex: 0x2B1D24)
}

private extension Color {
    /// An sRGB colour from `0xRRGGBB`.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension EnvironmentValues {
    /// The effective theme's colours. Classic until a root says otherwise.
    @Entry var palette: Palette = .classic
}

extension View {
    /// Applies `palette` to everything below: the colours every view reads and, on iPhone, the
    /// tint system controls take and the appearance. Set once, at each app's root.
    func palette(_ palette: Palette) -> some View {
        modifier(PaletteRoot(palette: palette))
    }

    /// A sheet's content. A sheet already on screen keeps the appearance it was presented
    /// with, whatever the root asks later, so a theme chosen inside Settings (or arriving
    /// from the watch, or a lapse of Pro) left an open sheet in the old light or dark mode:
    /// Pastel's canvas under white text, or black text on black. Each sheet asks for the
    /// palette's own appearance and tint. Nothing on the watch, whose screens stay dark.
    func paletteSheet() -> some View {
        modifier(PaletteSheet())
    }

    /// A bar button or a neutral glass control: grey glass with the label in the label
    /// colour, in every theme, as Classic draws it, rather than in the root's accent.
    func neutralGlass() -> some View {
        modifier(NeutralGlass())
    }

    /// A watch screen whose navigation title wears the accent: Classic's blue, the asset
    /// catalog's AccentColor, or Pastel's pink. Does nothing on iPhone, whose root tint
    /// reaches its titles.
    func accentTitle() -> some View {
        modifier(AccentTitle())
    }
}

private struct AccentTitle: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        #if os(watchOS)
        // One modifier whatever the theme, so a change of theme never replaces the screen.
        content.toolbarForegroundStyle(palette.accent ?? .accentColor, for: .navigationBar)
        #else
        content
        #endif
    }
}

private struct NeutralGlass: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content.tint(palette.glassTint)
    }
}

private struct PaletteSheet: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .tint(palette.accent)
            .preferredColorScheme(palette.colorScheme)
        #else
        content
        #endif
    }
}

private struct PaletteRoot: ViewModifier {
    let palette: Palette

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .environment(\.palette, palette)
            .tint(palette.accent)
            .preferredColorScheme(palette.colorScheme)
        #else
        // No tint at the watch's root: there a tint fills every glass button and toolbar
        // item with it. The screens whose titles take the accent set it themselves
        // (`accentTitle()`).
        content
            .environment(\.palette, palette)
        #endif
    }
}

extension IntervalPhase.Kind {
    /// The phase's own figure (`defaultSymbol`): the sun coming up and going down for the
    /// two ends of the session, and wind, not pause.circle.fill, for Rest: that sat directly
    /// above the Pause control and read as a second pause button.
    var symbolName: String { defaultSymbol.systemName }

    /// The word shown inside the ring. Short enough for the top chord of a 40mm ring;
    /// "COOLDOWN", the longest, relies on the run screen's label scaling to about 0.69.
    var shortTitle: String {
        switch self {
        case .prepare: "Ready"
        case .warmup: "Warmup"
        case .work: "Work"
        case .rest: "Rest"
        case .cooldown: "Cooldown"
        }
    }
}

extension Font {
    /// Hero numerals: SF Rounded, bold, monospaced digits.
    static func hero(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }

    /// Small uppercase phase words. Apply `.textCase(.uppercase)` and `.kerning(0.6)` at use.
    static let phaseLabel: Font = .footnote.weight(.semibold)
}
