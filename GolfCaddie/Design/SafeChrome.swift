import SwiftUI

/// Where on-screen controls may sit, for one `DisplayContext`. Pure value
/// type, in WINDOW coordinates (origin top-left of the full window, safe areas
/// ignored), shared by every layout so the Duo v2 rules hold everywhere:
///
/// - controls sit at least `edgeInset` (24 pt) from every window edge;
/// - more at the corners: nothing inside the `cornerInset` (36 pt) square at
///   each corner, so a control 24 pt from one edge must be >= 36 pt from the
///   other (the Duo's corners are rounded far more than an iPhone's, and the
///   cover screen's are tighter still);
/// - nothing straddles the hinge: on the expanded (unfolded) Duo a band
///   `hingeBandWidth` wide runs through the window centre — vertical when the
///   window is landscape, horizontal when portrait — and controls stay off it;
/// - every tap target is at least `minTapTarget` (44 pt).
///
/// System safe areas (Dynamic Island, home indicator) are NOT included; merge
/// them with `insets(including:)`.
struct SafeChrome: Equatable, Sendable {
    /// Minimum gap between a control and any window edge.
    static let edgeInset: CGFloat = 24
    /// Side of the keep-clear square at each window corner.
    static let cornerInset: CGFloat = 36
    /// Apple HIG minimum tap target (same as `InRoundMetrics.minTouch`).
    static let minTapTarget: CGFloat = InRoundMetrics.minTouch
    /// Hinge keep-out band: the existing gutter on each side of the hinge line.
    static let hingeBandWidth: CGFloat = RoundStageGeometry.hingeGutter * 2

    let display: DisplayContext

    init(display: DisplayContext) {
        self.display = display
    }

    /// The expanded window is the unfolded Duo (the app is iPhone-only), so it
    /// has a hinge through its centre whatever the posture reading says (the
    /// simulator reports `.unknown`). Compact windows never do.
    var hasHinge: Bool { display.layoutClass == .expanded }

    /// Hinge band for the context's own window, or nil without a hinge.
    var hingeExclusion: CGRect? { hingeExclusion(in: display.windowSize) }

    /// Hinge band for a window of `size` (hinge at its centre).
    func hingeExclusion(in size: CGSize) -> CGRect? {
        guard hasHinge, size.width > 0, size.height > 0 else { return nil }
        let half = Self.hingeBandWidth / 2
        if size.width > size.height {
            return CGRect(x: size.width / 2 - half, y: 0, width: Self.hingeBandWidth, height: size.height)
        }
        return CGRect(x: 0, y: size.height / 2 - half, width: size.width, height: Self.hingeBandWidth)
    }

    /// The panes controls may occupy in the context's window.
    func controlRegions() -> [CGRect] { controlRegions(in: display.windowSize) }

    /// The panes controls may occupy: the window inset by `edgeInset`, split
    /// in two pages around the hinge band when there is one. Corners are not
    /// cut out of these rects — anything placed in a region's outer corner
    /// must also clear `cornerExclusions` (check with `permits`).
    func controlRegions(in size: CGSize) -> [CGRect] {
        guard size.width > 0, size.height > 0 else { return [] }
        let inset = CGRect(origin: .zero, size: size)
            .insetBy(dx: Self.edgeInset, dy: Self.edgeInset)
        guard !inset.isNull, !inset.isEmpty else { return [] }
        guard let band = hingeExclusion(in: size) else { return [inset] }
        let pages: [CGRect]
        if size.width > size.height {
            pages = [
                CGRect(x: inset.minX, y: inset.minY, width: band.minX - inset.minX, height: inset.height),
                CGRect(x: band.maxX, y: inset.minY, width: inset.maxX - band.maxX, height: inset.height),
            ]
        } else {
            pages = [
                CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: band.minY - inset.minY),
                CGRect(x: inset.minX, y: band.maxY, width: inset.width, height: inset.maxY - band.maxY),
            ]
        }
        return pages.filter { $0.width > 0 && $0.height > 0 }
    }

    /// The four `cornerInset` squares controls must stay out of.
    func cornerExclusions() -> [CGRect] { cornerExclusions(in: display.windowSize) }

    func cornerExclusions(in size: CGSize) -> [CGRect] {
        let side = Self.cornerInset
        guard size.width > 0, size.height > 0 else { return [] }
        return [
            CGRect(x: 0, y: 0, width: side, height: side),
            CGRect(x: size.width - side, y: 0, width: side, height: side),
            CGRect(x: 0, y: size.height - side, width: side, height: side),
            CGRect(x: size.width - side, y: size.height - side, width: side, height: side),
        ]
    }

    /// Whether a control at `rect` (window coordinates) obeys every rule:
    /// inside one control region and clear of the corner squares. Touching an
    /// edge of a keep-out area is allowed; overlapping it is not.
    func permits(_ rect: CGRect) -> Bool {
        let size = display.windowSize
        let inRegion = controlRegions(in: size).contains { region in
            rect.minX >= region.minX && rect.maxX <= region.maxX
                && rect.minY >= region.minY && rect.maxY <= region.maxY
        }
        let hitsCorner = cornerExclusions(in: size).contains { Self.overlaps($0, rect) }
        return inRegion && !hitsCorner
    }

    /// Largest axis-aligned rect of the window free of every `occupied` rect —
    /// where the hole map should frame tee and green. Obstacles are clipped to
    /// the window; empty ones are ignored. The hinge band is not an obstacle
    /// (the map is a picture and may run under it); append `hingeExclusion` to
    /// `occupied` when it should be. Returns `.zero` when nothing is free.
    func unobstructedRect(windowSize: CGSize, occupied: [CGRect]) -> CGRect {
        guard windowSize.width > 0, windowSize.height > 0 else { return .zero }
        let window = CGRect(origin: .zero, size: windowSize)
        let obstacles = occupied
            .map { $0.intersection(window) }
            .filter { !$0.isNull && $0.width > 0 && $0.height > 0 }
        // Every maximal empty rectangle has its edges on the window edges or
        // on obstacle edges, so trying all those coordinate pairs is exact.
        let xs = Self.edges(window.minX, window.maxX, obstacles.flatMap { [$0.minX, $0.maxX] })
        let ys = Self.edges(window.minY, window.maxY, obstacles.flatMap { [$0.minY, $0.maxY] })
        var best = CGRect.zero
        for (i, x0) in xs.enumerated() {
            for x1 in xs[(i + 1)...] {
                for (j, y0) in ys.enumerated() {
                    for y1 in ys[(j + 1)...] {
                        let candidate = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
                        guard Self.area(candidate) > Self.area(best) else { continue }
                        if !obstacles.contains(where: { Self.overlaps($0, candidate) }) {
                            best = candidate
                        }
                    }
                }
            }
        }
        return best
    }

    /// Per-edge maximum of the system safe area and `edgeInset`.
    func insets(including safeArea: EdgeInsets) -> EdgeInsets {
        EdgeInsets(top: max(safeArea.top, Self.edgeInset),
                   leading: max(safeArea.leading, Self.edgeInset),
                   bottom: max(safeArea.bottom, Self.edgeInset),
                   trailing: max(safeArea.trailing, Self.edgeInset))
    }

    // MARK: Helpers

    /// Strict overlap (shared edges don't count).
    private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX < b.maxX && b.minX < a.maxX && a.minY < b.maxY && b.minY < a.maxY
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }

    private static func edges(_ low: CGFloat, _ high: CGFloat, _ inner: [CGFloat]) -> [CGFloat] {
        Array(Set([low, high] + inner)).sorted()
    }
}

extension View {
    /// Pads by `SafeChrome.edgeInset` on `edges`. For chrome laid out against
    /// the window edge (inside an `ignoresSafeArea` container); corner and
    /// hinge rules still apply on top (see `SafeChrome.permits`).
    func safeChromePadding(_ edges: Edge.Set = .all) -> some View {
        padding(edges, SafeChrome.edgeInset)
    }
}
