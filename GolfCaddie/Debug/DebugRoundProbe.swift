#if DEBUG
import SwiftUI

/// Invisible 1×1 accessibility element on the round screen (only with
/// `-DebugPostureControls 1`) that lets a UI test read round state that has
/// no visible label: `hole=4;round=<uuid>;stage=openWide;layout=expanded;posture=open`.
/// `hole` is the hole on screen; `stage` the `RoundMapLayout`.
struct DebugRoundProbe: View {
    static let identifier = "debug.roundProbe"

    let holeNumber: Int
    let roundID: UUID?
    let stage: RoundMapLayout
    @Environment(\.displayContext) private var display

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel("Debug round probe")
            .accessibilityValue(Self.value(holeNumber: holeNumber, roundID: roundID,
                                           stage: stage, display: display))
            .accessibilityIdentifier(Self.identifier)
    }

    static func value(holeNumber: Int, roundID: UUID?, stage: RoundMapLayout,
                      display: DisplayContext) -> String {
        [
            "hole=\(holeNumber)",
            "round=\(roundID?.uuidString ?? "none")",
            "stage=\(stage.rawValue)",
            "layout=\(display.layoutClass)",
            "posture=\(display.posture)",
        ].joined(separator: ";")
    }
}
#endif
