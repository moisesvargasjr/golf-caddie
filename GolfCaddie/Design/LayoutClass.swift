import SwiftUI
import UIKit

/// Width class the app lays out for. Computed ONCE at the root (window size +
/// size classes) and injected through the environment, so every screen agrees
/// on which layout family it is in.
///
/// - `.compact`: a regular iPhone, or the iPhone Duo's narrow cover screen
///   (466×678 pt). Today's layouts, unchanged.
/// - `.expanded`: the iPhone Duo's unfolded inner screen (951×669 pt in its
///   native landscape, 669×951 pt rotated). Two-column layouts.
///
/// Driven by the available size, never by interface orientation (Apple: the
/// inner display ignores the supported-orientations list).
enum LayoutClass: Equatable, Sendable {
    case compact
    case expanded

    /// Shorter window side at which a layout counts as expanded. The Duo inner
    /// screen's short side is 669 pt; the cover's is 466 pt; a Pro Max in
    /// landscape is ~440 pt tall, so it stays compact.
    static let expandedMinShortSide: CGFloat = 600

    static func resolve(windowSize: CGSize,
                        horizontal: UserInterfaceSizeClass?,
                        vertical: UserInterfaceSizeClass?) -> LayoutClass {
        guard windowSize.width > 0, windowSize.height > 0 else { return .compact }
        if min(windowSize.width, windowSize.height) >= expandedMinShortSide { return .expanded }
        // Regular × regular (iPad-like) windows are expanded even when smaller.
        // Regular width alone is NOT enough: a Pro Max in landscape reports it.
        if horizontal == .regular, vertical == .regular { return .expanded }
        return .compact
    }
}

/// Fold state of the device hinge, from `UIHingeInteraction` (iOS 27.1+).
/// `.unknown` on devices without a hinge or older systems.
enum HingePosture: Equatable, Sendable {
    case unknown
    case closed
    case halfOpen
    case open
}

/// Everything adaptive layouts need to know about the display, resolved once
/// at the root.
struct DisplayContext: Equatable, Sendable {
    var layoutClass: LayoutClass = .compact
    var posture: HingePosture = .unknown
    /// Full window size (ignoring safe areas). The Duo hinge runs through the
    /// window's center, so `windowSize / 2` locates it.
    var windowSize: CGSize = .zero

    var isLandscape: Bool { windowSize.width > windowSize.height }
}

extension EnvironmentValues {
    @Entry var layoutClass: LayoutClass = .compact
    @Entry var displayContext: DisplayContext = DisplayContext()
}

// MARK: - Root modifier

/// Measures the window and observes the hinge, then injects `layoutClass` and
/// `displayContext`. Apply once, at the app root.
private struct AdaptiveLayoutRoot: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var windowSize: CGSize = .zero
    @State private var posture: HingePosture = .unknown

    func body(content: Content) -> some View {
        let context = resolvedContext
        content
            .environment(\.layoutClass, context.layoutClass)
            .environment(\.displayContext, context)
            .background {
                HingeObserver(posture: $posture)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    // Size + safe-area insets = the whole window (a background
                    // is bounded by its content's safe area even when it
                    // ignores it). The hinge is located from this.
                    .onGeometryChange(for: CGSize.self) { proxy in
                        let insets = proxy.safeAreaInsets
                        return CGSize(width: proxy.size.width + insets.leading + insets.trailing,
                                      height: proxy.size.height + insets.top + insets.bottom)
                    } action: { size in
                        windowSize = size
                        #if DEBUG
                        NSLog("[Layout] window=\(Int(size.width))x\(Int(size.height)) class=\(resolvedContext.layoutClass) posture=\(posture)")
                        #endif
                    }
            }
    }

    private var resolvedContext: DisplayContext {
        var context = DisplayContext(
            layoutClass: LayoutClass.resolve(windowSize: windowSize,
                                             horizontal: horizontalSizeClass,
                                             vertical: verticalSizeClass),
            posture: posture,
            windowSize: windowSize
        )
        #if DEBUG
        context = DebugLayoutOverride.apply(to: context)
        #endif
        return context
    }
}

/// Keeps a full-width page (Home, Settings) readable and off the hinge on the
/// expanded screen: landscape → the left page (up to the hinge gutter);
/// portrait → a centred ~560 pt column. Compact: unchanged.
private struct ReadableOnExpanded: ViewModifier {
    @Environment(\.displayContext) private var display
    static let readableWidth: CGFloat = 560
    static let hingeGutter: CGFloat = 16

    func body(content: Content) -> some View {
        if display.layoutClass == .expanded, display.windowSize.width > 0 {
            if display.isLandscape {
                content
                    .frame(maxWidth: min(Self.readableWidth,
                                         display.windowSize.width / 2 - Self.hingeGutter))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                content
                    .frame(maxWidth: Self.readableWidth)
                    .frame(maxWidth: .infinity)
            }
        } else {
            content
        }
    }
}

extension View {
    /// See `ReadableOnExpanded`.
    func readableOnExpanded() -> some View {
        modifier(ReadableOnExpanded())
    }

    /// Inject `layoutClass` / `displayContext` for the whole tree.
    func adaptiveLayoutRoot() -> some View {
        modifier(AdaptiveLayoutRoot())
    }
}

// MARK: - Hinge observation

/// Hosts a `UIHingeInteraction` (UIKit, iOS 27.1 SDK — the only public
/// hinge/posture API; SwiftUI has no environment value for it) and publishes
/// its status. No-op before iOS 27.1 or on devices without a hinge.
private struct HingeObserver: UIViewRepresentable {
    @Binding var posture: HingePosture

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        if #available(iOS 27.1, *) {
            let interaction = UIHingeInteraction { _, update in
                let next = HingeObserver.posture(from: update.hinge)
                Task { @MainActor in
                    if posture != next { posture = next }
                }
            }
            view.addInteraction(interaction)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    @available(iOS 27.1, *)
    private static func posture(from hinge: UIHinge?) -> HingePosture {
        guard let hinge else { return .unknown }
        switch hinge.status {
        case .closed: return .closed
        case .partiallyOpen: return .halfOpen
        case .fullyOpen: return .open
        default: return .unknown
        }
    }
}

#if DEBUG
/// `-DebugLayoutClass compact|expanded` and `-DebugPosture halfOpen|open|closed`
/// force the resolved context — for screenshots when the simulator's hinge
/// can't be driven from the command line.
enum DebugLayoutOverride {
    static func apply(to context: DisplayContext) -> DisplayContext {
        var context = context
        let defaults = UserDefaults.standard
        switch defaults.string(forKey: "DebugLayoutClass") {
        case "expanded": context.layoutClass = .expanded
        case "compact": context.layoutClass = .compact
        default: break
        }
        switch defaults.string(forKey: "DebugPosture") {
        case "halfOpen": context.posture = .halfOpen
        case "open": context.posture = .open
        case "closed": context.posture = .closed
        default: break
        }
        return context
    }
}
#endif
