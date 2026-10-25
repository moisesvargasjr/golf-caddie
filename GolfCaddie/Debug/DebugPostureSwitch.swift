#if DEBUG
import Foundation
import Observation

/// A Duo pose the debug switch can force.
enum DebugPose: String, CaseIterable, Sendable {
    case closed
    case open
    case halfOpen

    /// Raw value, or the aliases `fold` / `unfold` / `book`.
    init?(name: String) {
        let aliases: [String: DebugPose] = ["fold": .closed, "unfold": .open, "book": .halfOpen]
        guard let pose = aliases[name] ?? DebugPose(rawValue: name) else { return nil }
        self = pose
    }

    var layoutClass: LayoutClass {
        self == .closed ? .compact : .expanded
    }

    var posture: HingePosture {
        switch self {
        case .closed: return .closed
        case .open: return .open
        case .halfOpen: return .halfOpen
        }
    }
}

/// One `pose:seconds` entry of `-DebugPostureSequence`.
struct DebugPostureStep: Equatable, Sendable {
    let pose: DebugPose
    let seconds: TimeInterval
}

enum DebugPostureScript {
    /// Parses `"closed:3,open:3,halfOpen:3"` (pose:seconds, comma separated;
    /// aliases allowed). Nil when empty or when any entry is malformed — a
    /// typo should fail loudly, not run half a script.
    static func parse(_ text: String) -> [DebugPostureStep]? {
        let entries = text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let steps = entries.compactMap(parseStep)
        guard !steps.isEmpty, steps.count == entries.count else { return nil }
        return steps
    }

    private static func parseStep(_ entry: String) -> DebugPostureStep? {
        let parts = entry.split(separator: ":", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let pose = DebugPose(name: parts[0]),
              let seconds = TimeInterval(parts[1]),
              seconds.isFinite, seconds > 0 else { return nil }
        return DebugPostureStep(pose: pose, seconds: seconds)
    }
}

/// DEBUG-only runtime fold / unfold / book switch. `AdaptiveLayoutRoot` reads
/// it (through `DebugLayoutOverride`) on every render, so changing it re-lays
/// out the running app exactly like a real fold, without the Simulator's
/// controls (simctl can't fold).
///
/// Driven by launch arguments (NSUserDefaults argument domain):
/// - `-DebugLayoutClass compact|expanded`, `-DebugPosture closed|open|halfOpen`
///   — initial overrides (unchanged meaning).
/// - `-DebugPostureSequence "closed:3,open:3,halfOpen:3"` — apply each pose in
///   order, holding it for its seconds; add `-DebugPostureSequenceLoop 1` to
///   repeat forever.
/// - `-DebugPostureControls 1` — listen for Darwin notifications
///   `com.moisesvargasjr.golfcaddie.debug.posture.<closed|open|halfOpen>`
///   (a UI test posts them; see `GolfCaddieUITests`), and expose the
///   `debug.roundProbe` accessibility element on the round screen.
///
/// Overriding the class only forces the class: the window size stays the
/// real one (compact on the 951×669 inner window draws the compact layout
/// stretched), as `-DebugLayoutClass` always did.
@Observable
@MainActor
final class DebugPostureSwitch {
    static let shared = DebugPostureSwitch(defaults: .standard)

    enum Key {
        static let layoutClass = "DebugLayoutClass"
        static let posture = "DebugPosture"
        static let sequence = "DebugPostureSequence"
        static let loop = "DebugPostureSequenceLoop"
        static let controls = "DebugPostureControls"
    }

    nonisolated static let darwinPrefix = "com.moisesvargasjr.golfcaddie.debug.posture."

    private(set) var layoutClass: LayoutClass?
    private(set) var posture: HingePosture?
    /// `-DebugPostureControls 1`: Darwin switch + round probe are on.
    private(set) var controlsEnabled: Bool

    private let defaults: UserDefaults
    @ObservationIgnored private var sequenceTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var isObservingDarwin = false

    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.layoutClass = Self.layoutClass(named: defaults.string(forKey: Key.layoutClass))
        self.posture = Self.posture(named: defaults.string(forKey: Key.posture))
        self.controlsEnabled = defaults.bool(forKey: Key.controls)
    }

    // MARK: Overrides

    func apply(to context: DisplayContext) -> DisplayContext {
        DisplayContext(layoutClass: layoutClass ?? context.layoutClass,
                       posture: posture ?? context.posture,
                       windowSize: context.windowSize)
    }

    func set(_ pose: DebugPose) {
        layoutClass = pose.layoutClass
        posture = pose.posture
        NSLog("[DebugPosture] \(pose.rawValue)")
    }

    func set(layoutClass: LayoutClass?, posture: HingePosture?) {
        self.layoutClass = layoutClass
        self.posture = posture
    }

    /// Back to the live hinge / window reading.
    func clear() {
        set(layoutClass: nil, posture: nil)
    }

    // MARK: Launch arguments

    /// Starts the launch-arg script and the Darwin listener. Idempotent; call
    /// once at launch (RootView does).
    func startFromLaunchArguments() {
        guard !hasStarted else { return }
        hasStarted = true
        if let text = defaults.string(forKey: Key.sequence) {
            if let steps = DebugPostureScript.parse(text) {
                runSequence(steps, loop: defaults.bool(forKey: Key.loop))
            } else {
                NSLog("[DebugPosture] ignoring malformed -DebugPostureSequence \"\(text)\"")
            }
        }
        if controlsEnabled, self === Self.shared {
            observeDarwinNotifications()
        }
    }

    /// Applies each step's pose then holds it for its seconds; loops when
    /// asked. Replaces any running script. `sleep` is injectable for tests.
    @discardableResult
    func runSequence(_ steps: [DebugPostureStep], loop: Bool,
                     sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
                         try await Task.sleep(for: .seconds($0))
                     }) -> Task<Void, Never> {
        sequenceTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard !steps.isEmpty else { return }
            repeat {
                for step in steps {
                    guard !Task.isCancelled, let self else { return }
                    self.set(step.pose)
                    do {
                        try await sleep(step.seconds)
                    } catch {
                        return
                    }
                }
            } while loop && !Task.isCancelled
        }
        sequenceTask = task
        return task
    }

    // MARK: Darwin notifications (UI tests)

    nonisolated static func darwinName(for pose: DebugPose) -> String {
        darwinPrefix + pose.rawValue
    }

    nonisolated static func pose(fromDarwinName name: String) -> DebugPose? {
        guard name.hasPrefix(darwinPrefix) else { return nil }
        return DebugPose(rawValue: String(name.dropFirst(darwinPrefix.count)))
    }

    /// An explicit switch wins over a running script.
    func handleDarwinNotification(named name: String) {
        guard let pose = Self.pose(fromDarwinName: name) else { return }
        sequenceTask?.cancel()
        sequenceTask = nil
        set(pose)
    }

    /// Only the shared instance listens (the C callback can't carry context).
    private func observeDarwinNotifications() {
        guard !isObservingDarwin else { return }
        isObservingDarwin = true
        Self.registerDarwinObservers(observer: UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        NSLog("[DebugPosture] listening for \(Self.darwinPrefix)<pose>")
    }

    /// Nonisolated so the callback literal is a plain C function, not a
    /// main-actor closure; it hops to the main actor itself.
    private nonisolated static func registerDarwinObservers(observer: UnsafeRawPointer) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let callback: CFNotificationCallback = { _, _, name, _, _ in
            guard let name else { return }
            let raw = name.rawValue as String
            Task { @MainActor in
                DebugPostureSwitch.shared.handleDarwinNotification(named: raw)
            }
        }
        for pose in DebugPose.allCases {
            CFNotificationCenterAddObserver(center, observer, callback,
                                            darwinName(for: pose) as CFString, nil,
                                            .deliverImmediately)
        }
    }

    // MARK: Parsing

    private static func layoutClass(named name: String?) -> LayoutClass? {
        switch name {
        case "expanded": return .expanded
        case "compact": return .compact
        default: return nil
        }
    }

    private static func posture(named name: String?) -> HingePosture? {
        switch name {
        case "halfOpen": return .halfOpen
        case "open": return .open
        case "closed": return .closed
        default: return nil
        }
    }
}
#endif
