import SwiftUI

/// Type system for "The Fairway Logbook".
///
/// Three families:
/// - **serif**: Georgia (with Times New Roman/Charter fallbacks) — display text, hole numerals, course names.
/// - **mono**: SF Mono / Menlo / Courier New — stamps, labels, all numerals.
/// - **ui**: SF Pro / system — buttons and incidental UI strings.
///
/// All numeric labels should be combined with `.tabularNumerals()` so columns align.
enum AppFont {
    // Family chains — SwiftUI's `Font.custom` falls back to system if the primary is missing.
    // Georgia ships with iOS so the primary should always resolve.
    static let serifName = "Georgia"
    static let monoName = "Menlo"  // SF Mono isn't a font name iOS exposes; Menlo is the next-best match.

    // MARK: - Display scale

    /// "The Fairway Logbook" masthead — 64pt serif bold.
    static let masthead = Font.custom(serifName, size: 64).weight(.bold)

    /// Course-name in Summary masthead — 38pt serif italic bold.
    static let courseName = Font.custom(serifName, size: 38).weight(.bold).italic()

    /// Hole numeral in Hole Detail header — 76pt serif bold.
    static let holeNumeral = Font.custom(serifName, size: 76).weight(.bold)

    /// 108pt serif tabular score on Summary.
    static let scoreHero = Font.custom(serifName, size: 108).weight(.bold)

    /// 64pt serif tabular distance on Active Round.
    static let distanceHero = Font.custom(serifName, size: 64).weight(.bold)

    /// "The Ledger." style italic section title — 22pt serif italic.
    static let sectionTitle = Font.custom(serifName, size: 22).weight(.bold).italic()

    /// 17pt serif body — also used for ledger row club names.
    static let bodyLarge = Font.custom(serifName, size: 17).weight(.bold)

    /// 24pt serif used in the "Begin new round" CTA.
    static let cta = Font.custom(serifName, size: 24).weight(.bold)

    /// 26pt serif used for score number in Hole Detail header.
    static let scoreMedium = Font.custom(serifName, size: 26).weight(.bold)

    // MARK: - Mono scale

    /// Stamp text — mono 10pt bold uppercase.
    static let stamp = Font.custom(monoName, size: 10).weight(.bold)

    /// 12pt mono bold uppercase — `Stamp(.md)`.
    static let stampMd = Font.custom(monoName, size: 12).weight(.bold)

    /// Metadata strips ("MAY · 18 · 2026 · ESCONDIDO, CA") — mono 11pt bold.
    static let metadata = Font.custom(monoName, size: 11).weight(.bold)

    /// Tiny mono label — 9pt bold, used in scorecard headers + caption hints.
    static let micro = Font.custom(monoName, size: 9).weight(.bold)

    /// 14pt mono numerals — scorecard cells, distance card FRONT/BACK.
    static let monoNumeral = Font.custom(monoName, size: 14).weight(.bold)

    /// 17pt mono — ledger YDS column.
    static let monoRow = Font.custom(monoName, size: 17).weight(.bold)
}

// MARK: - Tabular-numerals modifier

extension View {
    /// Apply this to any view containing numeric labels so columns align.
    /// SwiftUI's `.monospacedDigit()` is the supported path — it forces tabular figures
    /// while keeping the chosen font (Georgia / Menlo / system).
    func tabularNumerals() -> some View {
        self.monospacedDigit()
    }
}

// MARK: - Italic-the headline composer

/// Renders the recurring "*The* X." headline pattern — italic-regular "The"
/// followed by bold display text on separate lines. Matches the prototype
/// masthead "*The* / Fairway / Logbook.".
///
/// For shorter, single-line section titles ("Front nine.", "The Ledger.") use
/// a plain `Text(...).font(AppFont.sectionTitle)` instead.
///
/// Usage:
/// ```swift
/// ItalicHeadline(lines: ["The", "Fairway", "Logbook."], font: AppFont.masthead)
/// ```
struct ItalicHeadline: View {
    let lines: [String]
    let font: Font
    var color: Color? = nil
    var tracking: CGFloat = -2
    var lineSpacing: CGFloat = -6  // tightens line-height toward ~0.95 at masthead scale

    var body: some View {
        VStack(alignment: .leading, spacing: lineSpacing) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if line == "The" {
                    Text(line)
                        .font(font)
                        .fontWeight(.regular)
                        .italic()
                        .tracking(tracking)
                        .foregroundStyle(color ?? .primary)
                } else {
                    Text(line)
                        .font(font)
                        .fontWeight(.bold)
                        .tracking(tracking)
                        .foregroundStyle(color ?? .primary)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
