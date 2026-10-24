import CoreLocation
import Foundation

// Duo v2 PR 8: the pure pieces behind a finished round's course map (plan
// rule 12, "The card's MAP button"; CourseMapTests). The view code only reads
// these.

// MARK: - Round data → outlines

/// One hole of the round as the course map needs it: its score (by the
/// card's rules) and its placed shots in playing order.
struct CourseMapHole {
    let number: Int
    let par: Int?
    /// nil until the hole is finished or entered by hand.
    let score: Int?
    let shots: [CLLocationCoordinate2D]
}

enum CourseOutlineBuilder {
    /// The round's hole rows → course-map holes, sorted by number. A hole
    /// counts once it was confirmed or scored by hand (the same rule as the
    /// round score on the map screen); unplaced shots score but aren't drawn.
    /// A row without a par (a late-start hole scored with ADD) takes
    /// `coursePar`, so the badge, the outline and the caption all agree.
    static func holes(from rows: [Hole], shots: [UUID: [Shot]], penaltyStrokes: [UUID: Int],
                      coursePar: (Int) -> Int? = { _ in nil }) -> [CourseMapHole] {
        rows.sorted { $0.holeNumber < $1.holeNumber }.map { hole in
            let holeShots = (shots[hole.id] ?? []).sorted { $0.sequenceNumber < $1.sequenceNumber }
            let counts = hole.confirmedAt != nil || (hole.isHandScored && hole.handStrokes != nil)
            let score = counts
                ? HoleScoring.score(hole: hole, shots: holeShots, penaltyStrokes: penaltyStrokes[hole.id] ?? 0)
                : nil
            return CourseMapHole(number: hole.holeNumber, par: hole.par ?? coursePar(hole.holeNumber), score: score,
                                 shots: holeShots.compactMap(coordinate(of:)))
        }
    }

    /// One outline per hole that has something to draw, in hole order.
    ///
    /// - With a matched course (`anchors` returns a tee and/or green), every
    ///   anchored hole is drawn tee → shots → green — untracked holes too,
    ///   without a score, so they can still be opened.
    /// - Without one (`anchors` returns `.none`), only the shots are drawn: a
    ///   hole with no placed shot is left off the map.
    static func outlines(_ holes: [CourseMapHole], anchors: (Int) -> HolePathAnchors,
                         curatedPar: (Int) -> Int? = { _ in nil }) -> [CourseHoleOutline] {
        HoleScoring.holeRange.compactMap { number in
            let hole = holes.first { $0.number == number }
            let anchor = anchors(number)
            let shots = hole?.shots ?? []
            guard anchor.tee != nil || anchor.green != nil || !shots.isEmpty else { return nil }
            return CourseHoleOutline(number: number, tee: anchor.tee, green: anchor.green, shots: shots,
                                     score: hole?.score, par: hole?.par ?? curatedPar(number))
        }
    }

    private static func coordinate(of shot: Shot) -> CLLocationCoordinate2D? {
        guard let lat = shot.latitude, let lng = shot.longitude else { return nil }
        let c = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        return CLLocationCoordinate2DIsValid(c) ? c : nil
    }
}

// MARK: - What the course pose shows

/// Everything the course pose draws: the outlines and the header.
struct CourseMapContent {
    let outlines: [CourseHoleOutline]
    /// "Native Oaks".
    let title: String
    /// "OCT 18 · 82 (+10) · YOUR SHOTS ON EVERY HOLE".
    let caption: String
    /// The round has a matched course with tee/green anchors (else: shots only).
    let hasCourseAnchors: Bool

    /// Anything to put on the map at all (the card shows MAP only then).
    var hasContent: Bool { outlines.contains { !$0.route.isEmpty } }

    static let empty = CourseMapContent(outlines: [], title: CourseMapText.title(courseName: nil),
                                        caption: "", hasCourseAnchors: false)
}

enum CourseMapText {
    static let parOrBetter = "PAR OR BETTER"
    static let bogeyPlus = "BOGEY+"
    static let tapHint = "TAP A HOLE TO REVIEW IT"
    static let shotsOnlyHint = "NO COURSE LINKED · SHOTS ONLY"
    static let emptyHint = "NO SHOT LOCATIONS IN THIS ROUND"
    static let courseMapButton = "COURSE MAP"

    static func title(courseName: String?) -> String {
        let trimmed = courseName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "This round" : trimmed
    }

    static func caption(roundText: String, hasCourseAnchors: Bool) -> String {
        "\(roundText) · \(hasCourseAnchors ? "YOUR SHOTS ON EVERY HOLE" : "YOUR SHOTS ONLY")"
    }

    /// "OCT 18 · 82 (+10)" from every scored hole (drawn or not).
    static func roundText(dateText: String, holes: [CourseMapHole]) -> String {
        ReviewText.roundText(dateText: dateText, holes: holes.map { (par: $0.par, score: $0.score) })
    }
}

enum CourseMapAccessibilityID {
    static let chrome = "course.chrome"
    static let title = "course.title"
    static let legend = "course.legend"
    static let strip = "course.strip"
    static let backToCard = "course.card"
    /// COURSE MAP in a hole's review (glides back out).
    static let courseMapButton = "round.review.courseMap"
    /// A hole badge on the map (UIKit annotation view).
    static func badge(_ hole: Int) -> String { "course.badge.\(hole)" }
    /// A hole chip in the folded / iPhone strip.
    static func stripHole(_ hole: Int) -> String { "course.strip.\(hole)" }
}

// MARK: - Chrome per pose

/// How the course pose's controls sit over the map. Only the open Duo has a
/// board (Course-Open); folded and iPhone are not designed yet and get a
/// fallback: the full-screen map with a strip of hole chips.
enum CourseMapChromeStyle: Equatable {
    /// Course-Open: ‹ CARD + title top-left, the legend bottom-right.
    case openDuo
    /// Folded / iPhone portrait: title bar on top, hole chips across the bottom.
    case bottomStrip
    /// iPhone (and cover screen) landscape: title top-left, chips down the right.
    case sideStrip

    static func resolve(_ layout: RoundMapLayout) -> CourseMapChromeStyle {
        switch layout {
        case .openWide, .openPortrait, .book: return .openDuo
        case .folded, .phonePortrait: return .bottomStrip
        case .phoneLandscape: return .sideStrip
        }
    }
}
