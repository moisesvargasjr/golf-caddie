import SwiftUI

/// Collects where the visible chrome sits (window coordinates) so the map can
/// frame the hole into what's left (`SafeChrome.unobstructedRect`). Each
/// panel/box tags itself with `.reportsChromeFrame(_:)`; when the controls
/// auto-hide the boxes disappear, their frames drop out, and the map refits.
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
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                sink.report(id, frame)
            }
            .onDisappear { sink.report(id, nil) }
    }
}

extension View {
    /// This view covers part of the map; keep the hole out from under it.
    func reportsChromeFrame(_ id: String) -> some View {
        modifier(ChromeFrameReporter(id: id))
    }
}

enum ChromeFrames {
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
