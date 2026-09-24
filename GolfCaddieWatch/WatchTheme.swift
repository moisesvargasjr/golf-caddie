import SwiftUI
import WatchKit

/// The Watch design language — OLED black with warm Logbook ink + amber accent,
/// serif italics for hero numerals/names and a mono for labels/stats.
/// Mirrors the Claude Design "Golf Caddie Watch" tokens.
enum WT {
    /// B32 — the layout was hand-tuned on the 46mm Series 11 simulator
    /// (screen height 248 pt); on smaller watches (field device: Series 6,
    /// 40/44 mm) the fixed chrome + hero fonts overflowed the non-scrolling
    /// pages and clipped top/bottom. Scale the layout-driving constants by
    /// the actual screen height. Micro text (mono ≤ 12) stays unscaled —
    /// there's a readability floor — so only heroes and fixed frames wrap in
    /// `s()`.
    static let scale: CGFloat = min(1, WKInterfaceDevice.current().screenBounds.height / 248)

    /// A 46mm-tuned dimension, scaled for this screen.
    static func s(_ v: CGFloat) -> CGFloat { (v * scale).rounded() }

    static let bg = Color.black
    static let surface = Color(hex: 0x15140E)
    static let surface2 = Color(hex: 0x211E16)
    static let ink = Color(hex: 0xF1E8CF)
    static let ink2 = Color(hex: 0xA99E7F)
    static let ink3 = Color(hex: 0x6B6450)
    static let line = Color(hex: 0xF1E8CF).opacity(0.12)
    static let lineStrong = Color(hex: 0xF1E8CF).opacity(0.26)
    static let green = Color(hex: 0x86B66A)
    static let accent = Color(hex: 0xE7A33C)
    static let onAccent = Color(hex: 0x1B150A)

    /// Serif — hero numerals, club names, headlines. Italic by default. The
    /// system serif (New York): Georgia doesn't exist on watchOS, so the old
    /// `Font.custom("Georgia")` silently rendered everything in SF.
    static func serif(_ size: CGFloat, italic: Bool = true) -> Font {
        let f = Font.system(size: size, weight: .bold, design: .serif)
        return italic ? f.italic() : f
    }

    /// Mono — labels, stats, distances.
    static func mono(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
