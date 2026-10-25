#if DEBUG
import SwiftUI

/// Invisible 1×1 accessibility element on the round screen (only with
/// `-DebugPostureControls 1`) that lets a UI test read round state that has
/// no visible label: `hole=4;round=<uuid>;stage=openWide;layout=expanded;posture=open;`
/// `selected=<shot uuid|none>;question=<putts|penalty|none>;putts=2;paused=question,selection`.
/// `hole` is the hole on screen; `stage` the `RoundMapLayout`; the rest is the
/// screen-owned state a posture switch must keep.
struct DebugRoundProbe: View {
    static let identifier = "debug.roundProbe"

    let holeNumber: Int
    let roundID: UUID?
    let stage: RoundMapLayout
    var selectedShotID: UUID?
    var question: RoundMapQuestion?
    var puttsChoice: Int?
    var pauseReasons: Set<AutoHidePauseReason> = []
    @Environment(\.displayContext) private var display

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel("Debug round probe")
            .accessibilityValue(Self.value(holeNumber: holeNumber, roundID: roundID,
                                           stage: stage, display: display)
                + ";" + Self.screenState(selected: selectedShotID, question: question, putts: puttsChoice,
                                         paused: pauseReasons))
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

    static func screenState(selected: UUID?, question: RoundMapQuestion?, putts: Int?,
                            paused: Set<AutoHidePauseReason>) -> String {
        [
            "selected=\(selected?.uuidString ?? "none")",
            "question=\(question.map { "\($0)" } ?? "none")",
            "putts=\(putts.map(String.init) ?? "none")",
            "paused=\(paused.map { "\($0)" }.sorted().joined(separator: ","))",
        ].joined(separator: ";")
    }
}
#endif
