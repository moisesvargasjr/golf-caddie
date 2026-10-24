import CoreLocation
import Foundation

/// What the one round map is showing (Duo v2, Architecture A).
enum HoleMapMode: Equatable, Sendable {
    /// The hole being played: follows "you", draws the aim line to the green.
    case live
    /// A hole framed and fixed: a past hole mid-round or a finished round's review.
    case hole
    /// Every hole of the course: one line per hole plus a numbered badge.
    case course

    /// Shot pins can be dragged on any hole; never on the course overview.
    var allowsPinDrag: Bool { self != .course }
    /// "You" and the aim line belong to the live hole only.
    var showsUser: Bool { self == .live }
}

/// One hole as course mode draws it: tee → shots → green, plus its score.
struct CourseHoleOutline: Identifiable {
    let number: Int
    var tee: CLLocationCoordinate2D?
    var green: CLLocationCoordinate2D?
    /// Placed shots in playing order.
    var shots: [CLLocationCoordinate2D] = []
    var score: Int? = nil
    var par: Int? = nil

    var id: Int { number }

    /// The line course mode draws: tee, shots, green (whichever exist).
    var route: [CLLocationCoordinate2D] {
        [tee].compactMap { $0 } + shots + [green].compactMap { $0 }
    }

    /// Badge sits where the hole starts.
    var badgeCoordinate: CLLocationCoordinate2D? { route.first }

    /// Over-par holes are drawn amber (as on the canvas).
    var isOverPar: Bool {
        guard let score, let par else { return false }
        return score > par
    }

    var holeUpHeading: CLLocationDirection? {
        HoleFraming.holeUpHeading(tee: tee, green: green, shots: shots)
    }

    /// Change-detection key for the map (coordinates are not Equatable).
    var syncKey: String {
        let r = route.map { String(format: "%.6f,%.6f", $0.latitude, $0.longitude) }.joined(separator: ";")
        let s = score.map { String($0) } ?? "-"
        let p = par.map { String($0) } ?? "-"
        return "\(number)|\(s)|\(p)|\(r)"
    }
}

/// VoiceOver text for the map's pins and badges (one place, tested).
enum HoleMapAccessibility {
    static let shotHintDraggable = "Double-tap to select. Touch and hold, then drag, to move."
    static let shotHint = "Double-tap to select."
    static let youLabel = "You"
    static let greenLabel = "Green"

    /// "Shot 2, 7i, selected".
    static func shotLabel(number: Int, club: String?, selected: Bool) -> String {
        var parts = ["Shot \(number)"]
        if let club = club?.trimmingCharacters(in: .whitespacesAndNewlines), !club.isEmpty {
            parts.append(club)
        }
        if selected { parts.append("selected") }
        return parts.joined(separator: ", ")
    }

    /// "Hole 7, score 5, tap to review" (as on the course-map canvas).
    static func holeBadgeLabel(number: Int, score: Int?) -> String {
        guard let score else { return "Hole \(number), tap to review" }
        return "Hole \(number), score \(score), tap to review"
    }
}

/// Where a dropped pin lands: `ShotPlacement.pinned` — within 8 m of the
/// hole's walking path it snaps onto it, watch points first. The map reports
/// the snapped coordinate up; the caller saves the shot as `.manual`.
struct HoleMapShotSnapper {
    /// The hole's preferred trail (watch-first). Injected for tests.
    var trail: (UUID) -> [TracePoint]

    /// Production: the trail inside the hole's time window, read from the DB
    /// (synchronous GRDB read on drop, as `HoleDetailView` already does).
    static var live: HoleMapShotSnapper {
        HoleMapShotSnapper(trail: { ShotPlacement.trail(forHole: $0) })
    }

    func snappedCoordinate(for shot: Shot, droppedAt coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let pinned = ShotPlacement.pinned(shot, at: coordinate, trail: trail(shot.holeID))
        guard let lat = pinned.latitude, let lng = pinned.longitude else { return coordinate }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}
