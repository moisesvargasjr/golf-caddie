import CoreLocation
import SwiftUI

// Value models for the expanded (Duo inner screen) in-round layouts.
// `ActiveRoundView` builds them each render from the controller; the expanded
// subviews only read them and call `InRoundActions`, so a design direction can
// rearrange those subviews freely without touching round logic.

struct InRoundClubChip: Identifiable, Equatable {
    let club: Club
    /// Display-unit average carry ("142"), nil until enough samples.
    let avgText: String?
    let isSelected: Bool
    var id: String { club.id }
}

struct InRoundStrokeLine: Identifiable, Equatable {
    let id: UUID
    let number: Int
    let clubName: String
    /// Distance to the next logged shot ("152 yd"); nil for the latest shot.
    let distanceText: String?
    /// Where the shot came from: "WATCH", "PHONE", …
    let sourceText: String
}

struct InRoundPin: Equatable {
    let value: Int
    let unit: String
    let front: Int
    let back: Int
}

struct InRoundSnapshot {
    var holeNumber: Int
    var par: Int?
    /// "412 YD" from the curated course, when linked.
    var holeLengthText: String?
    var courseName: String?
    /// Running score vs par over confirmed holes, e.g. "+2 THRU 6".
    var scoreText: String?
    var pin: InRoundPin?
    var needsCourseLink: Bool
    /// "WATCH GPS" / "PHONE GPS" — which fix the pin distance uses.
    var pinSourceText: String?
    var gpsText: String
    var gpsColor: Color
    var clubs: [InRoundClubChip]
    /// "BAG · 11 OF 14"
    var bagText: String
    var strokes: [InRoundStrokeLine]
    var selectedClubShort: String?
    var shots: Int
    var penalties: Int
    var isMarking: Bool
    var canUndo: Bool
    var errorText: String?
    var isFollowingMap: Bool
    /// Watch app reachable → it is detecting swings.
    var watchDetecting: Bool
}

struct InRoundActions {
    /// Manual "+ SHOT" — the existing mark-shot action.
    let logShot: () -> Void
    /// "+ MISSED" — opens `MissingShotPinSheet`.
    let markMissed: () -> Void
    let putt: () -> Void
    let undo: () -> Void
    let finishHole: () -> Void
    let selectClub: (Club) -> Void
    let openBag: () -> Void
    let openCard: () -> Void
    let endRound: () -> Void
    let stepHole: (Int) -> Void
    let openHoleGrid: () -> Void
    let linkCourse: () -> Void
    let recenterMap: () -> Void
}

// MARK: - Pure helpers (unit tested)

@MainActor
enum InRoundFormat {
    /// "+2 THRU 6", "E THRU 3", "-1 THRU 9". Nil before the first confirmed
    /// hole. Holes without a par count toward THRU but not toward par.
    static func scoreText(holes: [(par: Int?, strokes: Int, confirmed: Bool)]) -> String? {
        let done = holes.filter(\.confirmed)
        guard !done.isEmpty else { return nil }
        let rated = done.compactMap { hole in hole.par.map { hole.strokes - $0 } }
        let toPar = rated.reduce(0, +)
        let label: String
        switch toPar {
        case 0: label = "E"
        case let n where n > 0: label = "+\(n)"
        default: label = "\(toPar)"
        }
        return "\(label) THRU \(done.count)"
    }

    static func sourceText(_ source: ShotSource) -> String {
        switch source {
        case .button, .actionButton: return "PHONE"
        case .manual: return "MANUAL"
        case .glasses: return "GLASSES"
        case .watchAuto: return "WATCH AUTO"
        case .watchManual: return "WATCH"
        case .reconstructed: return "TRACK"
        }
    }

    /// One line per shot; distance runs from each shot to the next one.
    static func strokeLines(shots: [Shot], units: Units) -> [InRoundStrokeLine] {
        shots.enumerated().map { index, shot in
            let next = index + 1 < shots.count ? shots[index + 1] : nil
            return InRoundStrokeLine(
                id: shot.id,
                number: shot.sequenceNumber,
                clubName: ClubCatalog.shared.shortName(id: shot.club) ?? "—",
                distanceText: distanceText(from: shot, to: next, units: units),
                sourceText: sourceText(shot.source)
            )
        }
    }

    private static func distanceText(from shot: Shot, to next: Shot?, units: Units) -> String? {
        guard let next,
              let a = coordinate(shot), let b = coordinate(next) else { return nil }
        let yards = Int(Distance.yards(fromMeters: Distance.meters(from: a, to: b)).rounded())
        let f = units.format(yards: yards)
        return "\(f.value) \(f.unit)"
    }

    private static func coordinate(_ shot: Shot) -> CLLocationCoordinate2D? {
        guard let lat = shot.latitude, let lng = shot.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}
