import SwiftUI

/// Design tokens for "The Fairway Logbook" aesthetic.
/// Hex values are verbatim from the design handoff (`design_handoff_golf_caddie/README.md`).
/// Do not change these without a design review.
struct PaletteValues: Equatable, Sendable {
    let paper: Color
    let paperDark: Color
    let ink: Color
    let ink2: Color
    let ink3: Color
    let rule: Color
    let ruleStrong: Color
    let red: Color
    let flag: Color
    /// RGB triple matching `ink` for paper-texture math (Canvas cross-hatch).
    let inkRgb: InkRgb
    /// Drop-shadow tuple for `PaperCard`. SwiftUI doesn't have a direct hard-shadow
    /// type, so consumers apply this via `.shadow(color:radius:x:y:)` with radius 0.
    let cardShadow: ShadowSpec

    struct ShadowSpec: Equatable, Sendable {
        let color: Color
        let x: CGFloat
        let y: CGFloat
    }

    struct InkRgb: Equatable, Sendable {
        let r: Double
        let g: Double
        let b: Double
    }
}

extension PaletteValues {
    /// Light mode — warm cream paper stock with dark forest "ink".
    static let light = PaletteValues(
        paper:      Color(hex: 0xEFE6D2),
        paperDark:  Color(hex: 0xE5DBC2),
        ink:        Color(hex: 0x1B3A29),
        ink2:       Color(hex: 0x3D5A48),
        ink3:       Color(hex: 0x7A8676),
        rule:       Color(hex: 0x1B3A29, opacity: 0.15),
        ruleStrong: Color(hex: 0x1B3A29, opacity: 0.35),
        red:        Color(hex: 0xA8392A),
        flag:       Color(hex: 0xC24A2D),
        inkRgb:     .init(r: 27.0 / 255.0, g: 58.0 / 255.0, b: 41.0 / 255.0),
        cardShadow: .init(color: Color(hex: 0x1B3A29, opacity: 0.18), x: 3, y: 3)
    )

    /// Dark mode — deep forest stock with warm cream "chalk".
    static let dark = PaletteValues(
        paper:      Color(hex: 0x16241C),
        paperDark:  Color(hex: 0x0F1A14),
        ink:        Color(hex: 0xEFE5C9),
        ink2:       Color(hex: 0xB5AC8E),
        ink3:       Color(hex: 0x6A6754),
        rule:       Color(hex: 0xEFE5C9, opacity: 0.16),
        ruleStrong: Color(hex: 0xEFE5C9, opacity: 0.4),
        red:        Color(hex: 0xE07A55),
        flag:       Color(hex: 0xE07A55),
        inkRgb:     .init(r: 239.0 / 255.0, g: 229.0 / 255.0, b: 201.0 / 255.0),
        cardShadow: .init(color: Color.black.opacity(0.55), x: 3, y: 3)
    )
}

// MARK: - Environment

private struct PaletteKey: EnvironmentKey {
    static let defaultValue: PaletteValues = .light
}

extension EnvironmentValues {
    var palette: PaletteValues {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - Color helpers

extension Color {
    /// Hex initializer — `Color(hex: 0x1B3A29)` or `Color(hex: 0x1B3A29, opacity: 0.15)`.
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
