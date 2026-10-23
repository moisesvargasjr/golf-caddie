import SwiftUI

/// Which in-round arrangement is on screen. Resolved from the root
/// `DisplayContext` (size + hinge), never from interface orientation.
enum RoundStageMode: Equatable, Sendable {
    /// Compact (iPhone / Duo cover): full-bleed map with floating cards and the
    /// bottom paper sheet — the original layout, pixel-identical.
    case overlay
    /// Expanded, taller than wide (inner screen turned portrait, flat):
    /// command center A — header, map left column, panel right, action bar.
    case commandPortrait
    /// Expanded, wider than tall, half-folded like a book (vertical hinge):
    /// A two-page split — map on the left page, panel on the right.
    case twoPage
    /// Expanded, wider than tall, fully open/flat: H4 — horizontal hole map
    /// with a control rail on the right (`WideRoundLayout`).
    case wide
    /// Expanded, taller than wide, half-folded (hinge horizontal): tabletop C —
    /// huge yardage above the hinge, controls below.
    case tabletop

    static func resolve(_ context: DisplayContext, isCasualMode: Bool) -> RoundStageMode {
        // Casual mode keeps its simple score stepper sheet on every screen.
        guard context.layoutClass == .expanded, !isCasualMode else { return .overlay }
        let halfOpen = context.posture == .halfOpen
        if context.isLandscape {
            return halfOpen ? .twoPage : .wide
        }
        return halfOpen ? .tabletop : .commandPortrait
    }

    var isExpanded: Bool { self != .overlay }
}

/// Where each slot of the in-round screen goes, as plain rects in the stage's
/// local coordinates. Pure so it can be unit tested and shared between the
/// `Layout` and anything that needs to know where the hinge is.
struct RoundStageGeometry: Equatable {
    var map: CGRect
    var header: CGRect
    var panel: CGRect
    var actions: CGRect
    /// Paper behind the panel: the right page (two-page) or everything.
    var page: CGRect

    /// Keep-out band either side of the hinge (Apple: nothing important on it).
    static let hingeGutter: CGFloat = 16
    static let margin: CGFloat = 16
    static let headerHeight: CGFloat = 60
    /// The two-row expanded action bar (44 pt secondary row + primary row).
    static let stackedActionBarHeight: CGFloat = 116
    /// Command-center portrait map column: ~316 of 626 pt in the mockup.
    static let portraitMapFraction: CGFloat = 0.505
    /// H4 wide control rail.
    static let wideRailWidth: CGFloat = 300
    /// Tabletop mini map width.
    static let tabletopMapWidth: CGFloat = 170

    /// - Parameter hinge: hinge position in local coordinates — x for the
    ///   landscape modes, y for tabletop. Defaults to the stage's center.
    static func make(mode: RoundStageMode, size: CGSize, hinge: CGFloat? = nil) -> RoundStageGeometry {
        let full = CGRect(origin: .zero, size: size)
        switch mode {
        case .overlay:
            return RoundStageGeometry(map: full, header: full, panel: full, actions: full, page: full)
        case .twoPage:
            return twoPage(size: size, hingeX: hinge ?? size.width / 2)
        case .wide:
            return wideRail(size: size)
        case .commandPortrait:
            return commandPortrait(size: size)
        case .tabletop:
            return tabletop(size: size, hingeY: hinge ?? size.height / 2)
        }
    }

    private static func twoPage(size: CGSize, hingeX: CGFloat) -> RoundStageGeometry {
        let x0 = hingeX + hingeGutter
        let width = max(0, size.width - x0 - margin)
        let header = CGRect(x: x0, y: 4, width: width, height: headerHeight)
        let actions = CGRect(x: x0, y: size.height - stackedActionBarHeight - 8,
                             width: width, height: stackedActionBarHeight)
        let panelTop = header.maxY + 8
        let panel = CGRect(x: x0, y: panelTop, width: width,
                           height: max(0, actions.minY - 8 - panelTop))
        // The map runs to the hinge; its own overlays keep a gutter (see
        // `mapChromeInsets`).
        let map = CGRect(x: 0, y: 0, width: max(0, hingeX), height: size.height)
        let page = CGRect(x: map.maxX, y: 0, width: max(0, size.width - map.maxX), height: size.height)
        return RoundStageGeometry(map: map, header: header, panel: panel, actions: actions, page: page)
    }

    /// H4: map across the left (the hinge falls inside it — it's only a
    /// picture), a ~300 pt control rail on the right.
    private static func wideRail(size: CGSize) -> RoundStageGeometry {
        let railX = max(0, size.width - margin - wideRailWidth)
        let actions = CGRect(x: railX, y: size.height - stackedActionBarHeight - 8,
                             width: wideRailWidth, height: stackedActionBarHeight)
        let panel = CGRect(x: railX, y: 8, width: wideRailWidth, height: max(0, actions.minY - 16))
        let map = CGRect(x: 0, y: 0, width: max(0, railX - margin), height: size.height)
        let page = CGRect(x: map.maxX, y: 0, width: max(0, size.width - map.maxX), height: size.height)
        return RoundStageGeometry(map: map, header: .zero, panel: panel, actions: actions, page: page)
    }

    private static func commandPortrait(size: CGSize) -> RoundStageGeometry {
        let header = CGRect(x: margin, y: 4, width: size.width - margin * 2, height: headerHeight)
        let actions = CGRect(x: margin, y: size.height - stackedActionBarHeight - 8,
                             width: size.width - margin * 2, height: stackedActionBarHeight)
        let bodyTop = header.maxY + 8
        let bodyHeight = max(0, actions.minY - 12 - bodyTop)
        let mapWidth = (size.width * portraitMapFraction).rounded()
        let map = CGRect(x: 0, y: bodyTop, width: mapWidth, height: bodyHeight)
        let panelX = mapWidth + 12
        let panel = CGRect(x: panelX, y: bodyTop, width: max(0, size.width - panelX - margin),
                           height: bodyHeight)
        return RoundStageGeometry(map: map, header: header, panel: panel, actions: actions,
                                  page: CGRect(origin: .zero, size: size))
    }

    private static func tabletop(size: CGSize, hingeY: CGFloat) -> RoundStageGeometry {
        let topBottom = max(0, hingeY - hingeGutter)
        let map = CGRect(x: size.width - margin - tabletopMapWidth, y: 8,
                         width: tabletopMapWidth, height: max(0, topBottom - 8))
        let header = CGRect(x: margin, y: 4, width: max(0, map.minX - margin * 2),
                            height: max(0, topBottom - 4))
        let lowerTop = hingeY + hingeGutter
        let panel = CGRect(x: margin, y: lowerTop, width: size.width - margin * 2,
                           height: max(0, size.height - lowerTop - 8))
        // Tabletop puts its actions inside the lower panel.
        return RoundStageGeometry(map: map, header: header, panel: panel, actions: .zero,
                                  page: CGRect(origin: .zero, size: size))
    }

    func rect(for role: RoundStageRole) -> CGRect {
        switch role {
        case .map: return map
        case .header: return header
        case .panel: return panel
        case .actions: return actions
        case .page: return page
        }
    }
}

/// Slot a child of `AdaptiveRoundLayout` occupies.
enum RoundStageRole: Sendable {
    case map, header, panel, actions, page
}

private struct RoundStageRoleKey: LayoutValueKey {
    static let defaultValue: RoundStageRole = .map
}

extension View {
    /// Tag a child of `AdaptiveRoundLayout` with the slot it fills.
    func roundStageRole(_ role: RoundStageRole) -> some View {
        layoutValue(key: RoundStageRoleKey.self, value: role)
    }
}

/// Places the in-round children by role. The container type never changes
/// between modes — only its `mode` — so every child keeps its identity across
/// fold/unfold: the single `MKMapView` (camera, follow mode) is moved and
/// resized, never rebuilt, and no `@State` below resets.
///
/// In `.overlay` every child gets the full bounds, centered — exactly what the
/// original `ZStack` did, so the compact layout is unchanged.
struct AdaptiveRoundLayout: Layout {
    var mode: RoundStageMode
    /// Hinge position in the stage's local coordinates (see
    /// `RoundStageGeometry.make`); nil = the stage's center.
    var hinge: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let geometry = RoundStageGeometry.make(mode: mode, size: bounds.size, hinge: hinge)
        for subview in subviews {
            let local = geometry.rect(for: subview[RoundStageRoleKey.self])
            let rect = local.offsetBy(dx: bounds.minX, dy: bounds.minY)
            subview.place(at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center,
                          proposal: ProposedViewSize(rect.size))
        }
    }
}
