import SwiftUI

/// The Watch design language — OLED black with warm Logbook ink + amber accent,
/// Georgia-serif italics for hero numerals/names and a mono for labels/stats.
/// Mirrors the Claude Design "Golf Caddie Watch" tokens.
enum WT {
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

    /// Serif (Georgia) — hero numerals, club names, headlines. Italic by default.
    static func serif(_ size: CGFloat, italic: Bool = true) -> Font {
        let f = Font.custom("Georgia", size: size).weight(.bold)
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

/// Suggest the club whose avg carry is closest to `yards`.
func suggestedClubIndex(_ clubs: [WatchClub], yards: Int) -> Int? {
    guard !clubs.isEmpty else { return nil }
    var best = 0
    var diff = Int.max
    for (i, c) in clubs.enumerated() {
        let d = abs(c.avgYards - yards)
        if d < diff { diff = d; best = i }
    }
    return best
}
