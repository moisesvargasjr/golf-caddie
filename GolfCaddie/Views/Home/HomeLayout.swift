import SwiftUI

/// Which Home arrangement a display gets.
///
/// - `.openWide`: the unfolded Duo held wide (also book pose, same window) —
///   the bag and Start a round on the left page; title, last entry and
///   logbook on the right (Home-Open mockup).
/// - `.single`: one column (Home-Folded mockup) for the folded Duo, and — not
///   designed yet — the regular iPhone and the open Duo held portrait.
enum HomeLayout: Equatable, Sendable {
    case openWide
    case single

    static func resolve(_ display: DisplayContext) -> HomeLayout {
        display.layoutClass == .expanded && display.isLandscape ? .openWide : .single
    }

    /// The two pages of an open-wide window, in window coordinates: the
    /// `SafeChrome` control regions (24 pt edges, hinge band excluded),
    /// pushed further in wherever the system safe area is larger. Nil unless
    /// the window is landscape with a hinge between two pages.
    static func pages(windowSize: CGSize, safeArea: EdgeInsets) -> (left: CGRect, right: CGRect)? {
        guard windowSize.width > windowSize.height else { return nil }
        let chrome = SafeChrome(display: DisplayContext(layoutClass: .expanded, posture: .open,
                                                        windowSize: windowSize))
        let regions = chrome.controlRegions(in: windowSize)
        guard regions.count == 2 else { return nil }
        let left = clamp(regions[0], to: windowSize, safeArea: safeArea)
        let right = clamp(regions[1], to: windowSize, safeArea: safeArea)
        guard left.width > 0, left.height > 0, right.width > 0, right.height > 0 else { return nil }
        return (left, right)
    }

    private static func clamp(_ rect: CGRect, to size: CGSize, safeArea: EdgeInsets) -> CGRect {
        let minX = max(rect.minX, safeArea.leading)
        let maxX = min(rect.maxX, size.width - safeArea.trailing)
        let minY = max(rect.minY, safeArea.top)
        let maxY = min(rect.maxY, size.height - safeArea.bottom)
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }
}

/// Accessibility identifiers for Home, shared by the screen and UI /
/// screenshot tests.
enum HomeID {
    static let root = "home.root"
    static let openWide = "home.layout.openWide"
    static let single = "home.layout.single"
    static let settings = "home.settings"
    static let watchStatus = "home.status.watch"
    static let glassesStatus = "home.status.g2"
    static let bag = "home.bag"
    static let bagPanel = "home.bagPanel"
    static let bagEditor = "home.bagEditor"
    static let lastEntry = "home.lastEntry"
    static let noEntry = "home.lastEntry.empty"
    static let logbook = "home.logbook"
    static let earlierRound = "home.earlierRound"
    static let startPanel = "home.start"
    static let modeTracking = "home.start.tracking"
    static let modeCasual = "home.start.casual"
    static let course = "home.start.course"
    static let holeDown = "home.start.holeDown"
    static let holeUp = "home.start.holeUp"
    static let startingHole = "home.start.hole"
    static let clubs = "home.start.clubs"
    static let begin = "home.begin"
    static let error = "home.error"
}
