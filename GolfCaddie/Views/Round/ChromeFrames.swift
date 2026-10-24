import SwiftUI

/// Collects where the visible chrome sits so the map can frame the hole into
/// what's left (`SafeChrome.unobstructedRect`). Each panel/box tags itself
/// with `.reportsChromeFrame(_:)`; when the controls auto-hide the boxes
/// disappear, their frames drop out, and the map refits.
///
/// Frames are measured in the screen's named coordinate space
/// (`ChromeFrames.space`), never `.global`: under DEBUG `-DebugWindowSize`
/// the whole app is drawn through `scaleEffect`, so global/UIWindow
/// coordinates are scaled while the map's own bounds are not. The map
/// reports its frame in the same space (`.reportsMapFrame`) and the free rect
/// is handed to it in the map's own coordinates.
struct ChromeFrameSink {
    var report: (String, CGRect?) -> Void = { _, _ in }
}

extension EnvironmentValues {
    @Entry var chromeFrameSink = ChromeFrameSink()
}

private struct ChromeFrameReporter: ViewModifier {
    let id: String
    @Environment(\.chromeFrameSink) private var sink

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ChromeFrames.space)) } action: { frame in
                sink.report(id, frame)
            }
            .onDisappear { sink.report(id, nil) }
    }
}

private struct MapFrameReporter: ViewModifier {
    @Environment(\.chromeFrameSink) private var sink

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ChromeFrames.space)) } action: { frame in
                sink.report(ChromeFrames.mapID, frame)
            }
    }
}

extension View {
    /// The map behind the chrome: its frame anchors the chrome frames.
    func reportsMapFrame() -> some View {
        modifier(MapFrameReporter())
    }

    /// This view covers part of the map; keep the hole out from under it.
    func reportsChromeFrame(_ id: String) -> some View {
        modifier(ChromeFrameReporter(id: id))
    }
}

enum ChromeFrames {
    /// Named coordinate space of the round map screen.
    static let space = "roundMapScreen"
    /// Sink id the map reports its own frame under (not chrome).
    static let mapID = "__map"

    /// Where to frame the hole, in the MAP's own coordinates (origin at the
    /// map's top-left, size = the map's size): `frames`, `mapFrame` and
    /// `safeRect` (the system safe area, if known) are in the same space
    /// (`space`). The result stays inside `safeRect`. nil for an empty map.
    static func unobstructedRect(display: DisplayContext, frames: [String: CGRect],
                                 mapFrame: CGRect, safeRect: CGRect? = nil) -> CGRect? {
        guard mapFrame.width > 0, mapFrame.height > 0 else { return nil }
        let toMap = { (rect: CGRect) in rect.offsetBy(dx: -mapFrame.minX, dy: -mapFrame.minY) }
        let sized = DisplayContext(layoutClass: display.layoutClass, posture: display.posture,
                                   windowSize: mapFrame.size)
        guard let free = unobstructedRect(display: sized, frames: frames.mapValues(toMap)) else { return nil }
        guard let safeRect, safeRect.width > 0, safeRect.height > 0 else { return free }
        let clipped = free.intersection(toMap(safeRect))
        return clipped.isNull || clipped.width < 1 || clipped.height < 1 ? free : clipped
    }

    /// Where to frame the hole: the largest window rect clear of every
    /// reported chrome frame; nil (the whole map) without a window size.
    static func unobstructedRect(display: DisplayContext, frames: [String: CGRect]) -> CGRect? {
        let size = display.windowSize
        guard size.width > 0, size.height > 0 else { return nil }
        let occupied = Array(frames.values)
        guard !occupied.isEmpty else { return CGRect(origin: .zero, size: size) }
        let free = SafeChrome(display: display).unobstructedRect(windowSize: size, occupied: occupied)
        return free.width > 0 && free.height > 0 ? free : nil
    }
}
