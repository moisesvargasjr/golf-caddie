import SwiftUI

/// Which arrangement of controls `RoundMapScreen` draws over the full-bleed
/// map (plan section 3). A pure function of `DisplayContext` — never of
/// interface orientation — so a fold, unfold or rotate only swaps the chrome;
/// the map, the hole session and every piece of screen state stay put.
enum RoundMapLayout: String, Equatable, Sendable, CaseIterable {
    /// Duo fully open, wide: command panel on the right with the club list
    /// down its right edge.
    case openWide
    /// Duo fully open, portrait: the same panel on the right, full height
    /// (split around the hinge); nothing across the bottom.
    case openPortrait
    /// Book pose: hole on the left page, command panel on the right page.
    case book
    /// Duo folded (cover screen): yardage card bottom-left; two stacked boxes
    /// on the right — actions on top, club list below.
    case folded
    /// iPhone portrait: one bottom panel in thumb reach; clubs scroll sideways.
    case phonePortrait
    /// iPhone landscape: panel on the right.
    case phoneLandscape

    static func resolve(_ display: DisplayContext) -> RoundMapLayout {
        if display.layoutClass == .expanded {
            guard display.isLandscape else {
                // Half-open while portrait (tabletop) has no design yet; the
                // open-portrait panel already keeps off the hinge.
                return .openPortrait
            }
            return display.posture == .halfOpen ? .book : .openWide
        }
        // The cover screen turned sideways has no design; it gets the iPhone
        // landscape panel, which fits its 678 × 466 window.
        if display.isLandscape { return .phoneLandscape }
        return display.posture == .closed ? .folded : .phonePortrait
    }

    /// Questions (putts, penalty) and the late-start entry open as a sheet
    /// across the bottom instead of inside a side panel.
    var asksInBottomSheet: Bool { self == .folded || self == .phonePortrait }

    /// + PENALTY lives in the ··· menu instead of the panel. Never on the
    /// live hole: folded shows it beside + SHOT (canvas Folded); the folded
    /// ··· keeps it only where that row isn't shown (past / casual holes).
    var penaltyInOverflow: Bool { false }

    /// The Duo's inner screen (rule: nothing on the hinge).
    var isOpenDuo: Bool { self == .openWide || self == .openPortrait || self == .book }
}

/// Where the chrome starts from each window edge: `SafeChrome.edgeInset`
/// (24 pt) or the system safe area, whichever is larger, with the corner rule
/// kept (a control 24 pt from one edge sits >= 36 pt from the other).
enum RoundChromeInsets {
    /// Gap kept above the home indicator / below the system bars on iPhone,
    /// as on the canvas (bottom 42 = 34 + 8).
    static let systemBarGap: CGFloat = 8

    static func make(safeArea: EdgeInsets) -> EdgeInsets {
        let edge = SafeChrome.edgeInset
        func clear(_ inset: CGFloat) -> CGFloat {
            inset > 0 ? max(inset + systemBarGap, edge) : edge
        }
        var insets = EdgeInsets(top: max(safeArea.top, edge),
                                leading: max(safeArea.leading, edge),
                                bottom: clear(safeArea.bottom),
                                trailing: max(safeArea.trailing, edge))
        // Corner rule: when both axes sit near the 24 pt minimum (the Duo,
        // no system bars), move the top and bottom out to the corner square.
        let corner = SafeChrome.cornerInset
        if min(insets.top, insets.bottom) < corner, min(insets.leading, insets.trailing) < corner {
            insets.top = max(insets.top, corner)
            insets.bottom = max(insets.bottom, corner)
        }
        return insets
    }
}
