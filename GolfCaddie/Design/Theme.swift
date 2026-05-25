import SwiftUI
import UIKit

// MARK: - User preferences

/// User-selectable theme mode. Persisted via `@AppStorage("themeMode")`.
enum ThemeMode: String, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto:  return "Auto"
        case .light: return "Light"
        case .dark:  return "Dark"
        }
    }
}

/// Distance unit. Persisted via `@AppStorage("units")`.
enum Units: String, CaseIterable, Identifiable {
    case yards, meters
    var id: String { rawValue }

    var label: String {
        switch self {
        case .yards:  return "Yards"
        case .meters: return "Meters"
        }
    }

    /// Short suffix used in UI ("yd" / "m").
    var suffix: String { self == .yards ? "yd" : "m" }

    /// Convert a yardage to the display unit and return an integer + suffix.
    func format(yards: Int) -> (value: Int, unit: String) {
        switch self {
        case .yards:  return (yards, "yd")
        case .meters: return (Int((Double(yards) * 0.9144).rounded()), "m")
        }
    }
}

// MARK: - Theme root modifier

/// Wraps a view tree, resolves the active palette from the user's `themeMode`
/// preference + system color scheme + clock-of-day, and injects it via
/// `\.palette` so descendant views can read tokens without prop drilling.
struct ThemedRoot: ViewModifier {
    @AppStorage("themeMode") private var themeRaw: String = ThemeMode.auto.rawValue
    @Environment(\.colorScheme) private var systemScheme

    func body(content: Content) -> some View {
        let mode = ThemeMode(rawValue: themeRaw) ?? .auto
        let isDark = Self.resolveDark(mode: mode, systemScheme: systemScheme)
        let palette: PaletteValues = isDark ? .dark : .light

        content
            .environment(\.palette, palette)
            .environment(\.colorScheme, isDark ? .dark : .light)
            .tint(palette.flag)
            .task(id: isDark) { Self.syncAppIcon(toDark: isDark) }
    }

    /// Mirror the resolved theme on the home-screen icon. `nil` = primary
    /// (light) icon; `"AppIcon-Dark"` = the dark variant declared via
    /// `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`. Skip the API call when
    /// already matching to avoid the system's "icon changed" alert flash.
    @MainActor
    static func syncAppIcon(toDark: Bool) {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons else { return }
        let target: String? = toDark ? "AppIcon-Dark" : nil
        if app.alternateIconName == target { return }
        app.setAlternateIconName(target)
    }

    /// In `.auto`, force dark when the system is dark OR the clock says "late".
    /// The clock rule (≥18:00 or <06:00) is part of the design spec — paper "ink"
    /// reads better as a warm cream under evening lighting.
    static func resolveDark(mode: ThemeMode, systemScheme: ColorScheme) -> Bool {
        switch mode {
        case .light: return false
        case .dark:  return true
        case .auto:
            if systemScheme == .dark { return true }
            let hour = Calendar.current.component(.hour, from: Date())
            return hour >= 18 || hour < 6
        }
    }
}

extension View {
    /// Apply once at the app root. Provides `\.palette` to every descendant.
    func themedRoot() -> some View { modifier(ThemedRoot()) }
}

// MARK: - Roman numerals

extension Int {
    /// Convert an Int to a Roman-numeral string. The design uses Roman everywhere
    /// a hole label is rendered (I…XVIII). Returns "" for non-positive numbers.
    var roman: String {
        guard self > 0 else { return "" }
        let table: [(Int, String)] = [
            (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
            (100, "C"),  (90, "XC"),  (50, "L"),  (40, "XL"),
            (10, "X"),   (9, "IX"),   (5, "V"),   (4, "IV"),
            (1, "I"),
        ]
        var n = self
        var out = ""
        for (value, glyph) in table {
            while n >= value {
                out += glyph
                n -= value
            }
        }
        return out
    }
}

// MARK: - View extension helpers

extension View {
    /// Hard offset shadow used by `PaperCard` — SwiftUI's `.shadow(radius:0)`
    /// gives the printed-card look (no soft blur). Pass the palette's `cardShadow`.
    func paperCardShadow(_ shadow: PaletteValues.ShadowSpec) -> some View {
        self.shadow(color: shadow.color, radius: 0, x: shadow.x, y: shadow.y)
    }
}
