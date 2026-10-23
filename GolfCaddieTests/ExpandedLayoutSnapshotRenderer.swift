import SwiftUI
import XCTest
@testable import GolfCaddie

/// Renders the expanded in-round layouts to PNGs for design review when the
/// simulator's hinge can't be posed from the command line. Opt-in: runs only
/// with `TEST_RUNNER_RENDER_DUO_SNAPSHOTS=<output dir>` set for xcodebuild.
/// The map is a placeholder (MapKit doesn't draw in `ImageRenderer`).
@MainActor
final class ExpandedLayoutSnapshotRenderer: XCTestCase {
    func testRenderExpandedLayouts() throws {
        guard let dir = ProcessInfo.processInfo.environment["RENDER_DUO_SNAPSHOTS"] else {
            throw XCTSkip("Set TEST_RUNNER_RENDER_DUO_SNAPSHOTS to render")
        }
        let cases: [(String, RoundStageMode, CGSize)] = [
            ("inround-portrait-after", .commandPortrait, CGSize(width: 669, height: 917)),
            ("inround-tabletop-after", .tabletop, CGSize(width: 669, height: 917)),
            ("inround-book-render-after", .twoPage, CGSize(width: 867, height: 635)),
            ("inround-wide-render-after", .wide, CGSize(width: 867, height: 635)),
        ]
        for (name, mode, size) in cases {
            let view = StagePreview(mode: mode)
                .frame(width: size.width, height: size.height)
                .environment(\.palette, .dark)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let data = renderer.uiImage?.pngData() else {
                XCTFail("render failed: \(name)")
                continue
            }
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}

private struct StagePreview: View {
    let mode: RoundStageMode

    var body: some View {
        AdaptiveRoundLayout(mode: mode, hinge: nil) {
            ZStack {
                Color(red: 0.25, green: 0.42, blue: 0.22)
                Text("MAP").font(.largeTitle.bold()).foregroundStyle(.white.opacity(0.6))
            }
            .roundStageRole(.map)
            switch mode {
            case .commandPortrait, .twoPage:
                CommandCenterChrome(snapshot: Self.snapshot, actions: Self.actions)
            case .wide:
                WideRoundLayout(snapshot: Self.snapshot, actions: Self.actions)
            case .tabletop:
                TabletopChrome(snapshot: Self.snapshot, actions: Self.actions)
            case .overlay:
                EmptyView()
            }
        }
    }

    static var clubs: [Club] { ClubConfiguration.recommendedDefault.bag.compactMap { ClubCatalog.shared.club(id: $0) } }

    static var snapshot: InRoundSnapshot {
        InRoundSnapshot(
            holeNumber: 7, par: 4, holeLengthText: "412 YD", courseName: "Rancho Bernardo Inn",
            scoreText: "+2 THRU 6",
            pin: InRoundPin(value: 152, unit: "yd", front: 138, back: 166),
            needsCourseLink: false, pinSourceText: "WATCH GPS",
            gpsText: "GPS ±4M", gpsColor: .white,
            clubs: clubs.enumerated().map { index, club in
                InRoundClubChip(club: club, avgText: "\(230 - index * 12)", isSelected: index == 5)
            },
            bagText: "BAG · \(clubs.count) OF \(clubs.count)",
            strokes: [
                InRoundStrokeLine(id: UUID(), number: 1, clubName: "Dr", distanceText: "248 yd", sourceText: "WATCH AUTO"),
                InRoundStrokeLine(id: UUID(), number: 2, clubName: "7i", distanceText: nil, sourceText: "PHONE"),
            ],
            selectedClubShort: "7i", shots: 2, penalties: 0, isMarking: false, canUndo: true,
            errorText: nil, isFollowingMap: false, watchDetecting: true
        )
    }

    static let actions = InRoundActions(
        logShot: {}, markMissed: {}, putt: {}, undo: {}, finishHole: {}, selectClub: { _ in },
        openBag: {}, openCard: {}, endRound: {}, stepHole: { _ in }, openHoleGrid: {},
        linkCourse: {}, recenterMap: {}
    )
}
