//
//  PaletteContrastTests.swift
//  IntervallyTests
//

import SwiftUI
import Testing
@testable import Intervally

/// Every colour pairing that carries text or a glyph, in WCAG 2 contrast, for both themes and
/// both devices' palettes, so a palette can't drift below what Theme.swift says it measured.
@Suite("Palette contrast")
@MainActor
struct PaletteContrastTests {

    nonisolated static let kinds: [IntervalPhase.Kind] = [.prepare, .warmup, .work, .rest, .cooldown]
    nonisolated static let palettes: [Palette] = [.classic, .pastelWatch, .pastelPhone]
    /// The palettes drawn on black: the watch's, and Classic everywhere.
    nonisolated static let blackPalettes: [Palette] = [.classic, .pastelWatch]

    // MARK: WCAG

    /// A colour as gamma-encoded extended sRGB with its opacity, which is how UIKit blends.
    private struct RGBA {
        var r, g, b, a: Double

        init(_ color: Color) {
            let resolved = color.resolve(in: EnvironmentValues())
            r = Double(resolved.red)
            g = Double(resolved.green)
            b = Double(resolved.blue)
            a = Double(resolved.opacity)
        }

        /// `self` drawn over an opaque `background`.
        func over(_ background: RGBA) -> RGBA {
            var out = background
            out.r = a * r + (1 - a) * background.r
            out.g = a * g + (1 - a) * background.g
            out.b = a * b + (1 - a) * background.b
            out.a = 1
            return out
        }

        /// Relative luminance. Extended sRGB shares Display P3's white and primaries' Y, so a
        /// P3 colour measures as it shows.
        var luminance: Double {
            func linear(_ c: Double) -> Double {
                let magnitude = abs(c)
                let value = magnitude <= 0.04045 ? magnitude / 12.92 : pow((magnitude + 0.055) / 1.055, 2.4)
                return c < 0 ? -value : value
            }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
    }

    /// The contrast of `foreground` drawn on `background`, each drawn over black first: the
    /// canvas every surface sits on is opaque.
    static func contrast(_ foreground: Color, on background: Color, over base: Color = .black) -> Double {
        let ground = RGBA(background).over(RGBA(base))
        let ink = RGBA(foreground).over(ground)
        let (lighter, darker) = (max(ink.luminance, ground.luminance), min(ink.luminance, ground.luminance))
        return (lighter + 0.05) / (darker + 0.05)
    }

    @Test("The measure agrees with WCAG's own anchors")
    func anchors() {
        #expect(abs(Self.contrast(.white, on: .black) - 21) < 0.01)
        #expect(abs(Self.contrast(.black, on: .black) - 1) < 0.001)
        // Classic's work blue, Display P3: Theme.swift says black on it is 9.9:1.
        #expect(abs(Self.contrast(.black, on: Theme.work) - 9.89) < 0.05)
    }

    // MARK: The watch, and every phase colour on black

    @Test("Every fill reads on black, mid-workout, at 7:1 or better", arguments: blackPalettes)
    func fillsOnBlack(palette: Palette) {
        for kind in Self.kinds {
            let ratio = Self.contrast(palette.fill(for: kind), on: .black)
            #expect(ratio >= 7, "\(palette.theme) \(kind): \(ratio)")
        }
    }

    @Test("Every dimmed variant is deeper than its fill, and still reads on black", arguments: palettes)
    func dimmed(palette: Palette) {
        for kind in Self.kinds {
            let fill = RGBA(palette.fill(for: kind)).luminance
            let dimmed = RGBA(palette.dimmed(for: kind)).luminance
            #expect(dimmed < fill, "\(palette.theme) \(kind)")
            #expect(Self.contrast(palette.dimmed(for: kind), on: .black) >= 4.5, "\(palette.theme) \(kind)")
        }
    }

    @Test("The label on a tinted capsule reads on every fill and dimmed variant", arguments: palettes)
    func onTint(palette: Palette) {
        // 7.5:1 where it is glanced at mid-set (the watch's completion screen and tinted
        // complication). The iPhone's Pastel pink is deeper for its light canvas, and its
        // capsule label is 17-point semibold, where 4.5:1 is already AAA.
        let brand = palette == .pastelPhone ? 6.0 : 7.5
        #expect(Self.contrast(palette.onTint, on: palette.work) >= brand, "\(palette.theme): the brand capsule")
        for kind in Self.kinds {
            #expect(Self.contrast(palette.onTint, on: palette.fill(for: kind)) >= 4.5, "\(palette.theme) \(kind)")
            // The complication's paused face and the bottom of the completion screen.
            #expect(Self.contrast(palette.onTint, on: palette.dimmed(for: kind)) >= 4.5, "\(palette.theme) \(kind) dimmed")
        }
    }

    @Test("Each phase keeps a colour of its own", arguments: palettes)
    func distinct(palette: Palette) {
        let fills = Self.kinds.map(palette.fill(for:))
        #expect(Set(fills).count == fills.count)
        let inks = Self.kinds.map(palette.ink(for:))
        #expect(Set(inks).count == inks.count)
    }

    @Test("On the watch, both themes keep the black screen, and phase text is the fill")
    func watchKeepsBlack() {
        for palette in [Palette.classic, .pastelWatch] {
            #expect(palette.canvas == .black)
            #expect(palette.colorScheme == .dark)
            #expect(palette.neutral == .white)
            for kind in Self.kinds {
                #expect(palette.ink(for: kind) == palette.fill(for: kind))
            }
        }
        #expect(Palette.of(.classic) == .classic)
        #expect(Palette.of(.pastel) == .pastelWatch)
    }

    @Test("Classic is exactly the colours Classic always had")
    func classicIsTheme() {
        let classic = Palette.classic
        for kind in Self.kinds {
            #expect(classic.fill(for: kind) == Theme.light(for: kind))
            #expect(classic.dimmed(for: kind) == Theme.dimmed(for: kind))
            #expect(classic.ink(for: kind) == Theme.light(for: kind))
            #expect(classic.track(for: kind) == Theme.track(for: kind))
        }
        #expect(classic.onTint == Theme.onTint)
        #expect(classic.brandDeep == Theme.brandDeep)
        #expect(classic.card == .white.opacity(0.10))
        #expect(classic.accent == nil)
        #expect(classic.glassTint == nil)
    }

    @Test("Pastel's work colour is pink, where Classic's is blue")
    func pastelIsPink() {
        let pink = RGBA(Palette.pastelWatch.work)
        #expect(pink.r > 0.95 && pink.r > pink.b && pink.b > pink.g)
    }

    // MARK: The iPhone

    @Test("Phase text reads on the iPhone's cards and canvas in both themes", arguments: [Palette.classic, .pastelPhone])
    func inkOnSurfaces(palette: Palette) {
        for kind in Self.kinds {
            let ink = palette.ink(for: kind)
            let onCard = Self.contrast(ink, on: palette.card, over: palette.canvas)
            let onCanvas = Self.contrast(ink, on: palette.canvas)
            #expect(onCard >= 4.5, "\(palette.theme) \(kind) on a card: \(onCard)")
            #expect(onCanvas >= 4.5, "\(palette.theme) \(kind) on the canvas: \(onCanvas)")
        }
    }

    @Test("Pastel's iPhone inks clear 5:1 on a card, with margin over AA")
    func pastelInkMargin() {
        let palette = Palette.pastelPhone
        for kind in Self.kinds {
            let ratio = Self.contrast(palette.ink(for: kind), on: palette.card, over: palette.canvas)
            #expect(ratio >= 5, "\(kind): \(ratio)")
        }
    }

    @Test("The neutral reads on the iPhone's cards: a rhythm line's rounds, at 80%", arguments: [Palette.classic, .pastelPhone])
    func neutralOnCards(palette: Palette) {
        let rounds = Self.contrast(palette.neutral.opacity(0.8), on: palette.card, over: palette.canvas)
        #expect(rounds >= 4.5, "\(palette.theme): \(rounds)")
    }

    @Test("Pastel's accent, the links and the selected tab, reads on the canvas and on white rows")
    func accent() throws {
        let palette = Palette.pastelPhone
        let accent = try #require(palette.accent)
        #expect(Self.contrast(accent, on: palette.canvas) >= 4.5)
        #expect(Self.contrast(accent, on: .white) >= 4.5)
        #expect(Self.contrast(accent, on: palette.card, over: palette.canvas) >= 4.5)
    }

    @Test("Pastel on iPhone is a light appearance with a light canvas")
    func pastelPhoneIsLight() {
        let palette = Palette.pastelPhone
        #expect(palette.colorScheme == .light)
        #expect(RGBA(palette.canvas).luminance > 0.9)
        #expect(RGBA(palette.card).luminance > 0.8)
        #expect(RGBA(palette.card).luminance < RGBA(palette.canvas).luminance, "Cards stand off the canvas")
    }

    // MARK: Pastel's two tiers, and colour vision

    @Test("Pastel on iPhone: every fill is deeper than the watch's, and the brand pink clears 3:1 on the canvas")
    func pastelPhoneTier() {
        for kind in Self.kinds {
            #expect(RGBA(Palette.pastelPhone.fill(for: kind)).luminance < RGBA(Palette.pastelWatch.fill(for: kind)).luminance, "\(kind)")
        }
        #expect(Self.contrast(Palette.pastelPhone.work, on: Palette.pastelPhone.canvas) >= 3)
    }

    /// Smallest CIELAB difference between two colours across normal vision and simulated
    /// protanopia, deuteranopia and tritanopia (Machado, Oliveira and Fernandes 2009, full
    /// severity, applied to linear sRGB).
    nonisolated static func apart(_ a: Color, _ b: Color) -> Double {
        let simulations: [[[Double]]?] = [
            nil,
            [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
            [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
            [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]],
        ]
        func linear(_ c: Color) -> [Double] {
            let r = c.resolve(in: EnvironmentValues())
            return [Double(r.linearRed), Double(r.linearGreen), Double(r.linearBlue)]
        }
        func lab(_ l: [Double]) -> [Double] {
            let c = l.map { min(max($0, 0), 1) }
            let x = (0.4124 * c[0] + 0.3576 * c[1] + 0.1805 * c[2]) / 0.95047
            let y = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
            let z = (0.0193 * c[0] + 0.1192 * c[1] + 0.9505 * c[2]) / 1.08883
            func f(_ t: Double) -> Double { t > 0.008856 ? pow(t, 1.0 / 3) : 7.787 * t + 16.0 / 116 }
            return [116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))]
        }
        func apply(_ matrix: [[Double]]?, _ v: [Double]) -> [Double] {
            guard let matrix else { return v }
            return matrix.map { row in row[0] * v[0] + row[1] * v[1] + row[2] * v[2] }
        }
        func distance(_ p: [Double], _ q: [Double]) -> Double {
            let d0 = p[0] - q[0], d1 = p[1] - q[1], d2 = p[2] - q[2]
            return (d0 * d0 + d1 * d1 + d2 * d2).squareRoot()
        }
        let la = linear(a), lb = linear(b)
        var smallest = Double.infinity
        for matrix in simulations {
            smallest = min(smallest, distance(lab(apply(matrix, la)), lab(apply(matrix, lb))))
        }
        return smallest
    }

    @Test("On the watch, Pastel's bordering phases stay apart for colour-blind eyes, work and rest most of all")
    func pastelApartOnTheWatch() {
        let p = Palette.pastelWatch
        #expect(Self.apart(p.work, p.rest) >= 30, "work/rest")
        for (a, b) in [(p.prepare, p.warmup), (p.warmup, p.work), (p.rest, p.cooldown), (p.work, p.cooldown), (p.prepare, p.work)] {
            #expect(Self.apart(a, b) >= 22)
        }
    }

    @Test("The colour-vision measure separates what it should and not what it shouldn't")
    func apartAnchors() {
        // Classic's blue and orange stay far apart in every simulation; its blue and green
        // only for the common deficiencies (tritanopes, about 1 in 10,000, see them close).
        #expect(Self.apart(Theme.work, Theme.warmup) > 60, "Classic's blue and orange")
        #expect(Self.apart(.white, .black) > 90)
        #expect(Self.apart(Theme.work, Theme.work) < 0.001)
    }
}
