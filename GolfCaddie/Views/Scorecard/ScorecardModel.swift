import CoreLocation
import Foundation

/// One hole's column on the physical scorecard. Nil values render blank.
struct ScorecardColumn: Equatable, Identifiable {
    let number: Int
    let yards: Int?
    let par: Int?
    let strokeIndex: Int?
    /// Strokes incl. penalties; nil until the hole is confirmed.
    let score: Int?
    let putts: Int?
    let gir: Bool?
    let penalties: Int?
    /// Club sequence / putts / penalties, e.g. "Dr · 7i · PW · 2 putts".
    let story: String?
    let holeID: UUID?
    let isConfirmed: Bool
    var id: Int { number }

    /// Score relative to par, when both are known.
    var toPar: Int? {
        guard let score, let par else { return nil }
        return score - par
    }
}

/// Mark drawn around a score: circle = birdie, double circle = eagle or
/// better, square = bogey, double square = double bogey or worse.
enum ScoreMark: Equatable {
    case none, circle, doubleCircle, square, doubleSquare

    static func mark(toPar: Int?) -> ScoreMark {
        guard let toPar else { return .none }
        switch toPar {
        case ...(-2): return .doubleCircle
        case -1: return .circle
        case 0: return .none
        case 1: return .square
        default: return .doubleSquare
        }
    }
}

struct ScorecardTotals: Equatable {
    let yards: Int?
    let par: Int?
    let score: Int?
    let putts: Int?
    let penalties: Int?
}

/// The whole card. Pure: built from persisted rows so it can be unit tested.
struct ScorecardModel: Equatable {
    let columns: [ScorecardColumn]   // always 18, holes 1…18
    let hasStrokeIndex: Bool

    var front: [ScorecardColumn] { Array(columns.prefix(9)) }
    var back: [ScorecardColumn] { Array(columns.suffix(9)) }

    var out: ScorecardTotals { Self.totals(front) }
    var inn: ScorecardTotals { Self.totals(back) }
    var total: ScorecardTotals { Self.totals(columns) }

    var girCount: Int { columns.filter { $0.gir == true }.count }

    /// Gross minus par over confirmed holes that have a par.
    var grossToPar: Int? {
        let rated = columns.compactMap(\.toPar)
        return rated.isEmpty ? nil : rated.reduce(0, +)
    }

    static func totals(_ cols: [ScorecardColumn]) -> ScorecardTotals {
        func sum(_ values: [Int?]) -> Int? {
            let known = values.compactMap { $0 }
            return known.isEmpty ? nil : known.reduce(0, +)
        }
        return ScorecardTotals(
            yards: sum(cols.map(\.yards)),
            par: sum(cols.map(\.par)),
            score: sum(cols.map(\.score)),
            putts: sum(cols.map(\.putts)),
            penalties: sum(cols.map(\.penalties))
        )
    }

    /// GIR: strokes before the first putt (penalties excluded) ≤ par − 2.
    static func greenInRegulation(shots: [Shot], par: Int?) -> Bool? {
        guard let par else { return nil }
        let ordered = shots.sorted { $0.sequenceNumber < $1.sequenceNumber }
        let beforeFirstPutt = ordered.firstIndex(where: \.isPutt) ?? ordered.count
        return beforeFirstPutt <= par - 2
    }

    struct HoleInput {
        let hole: Hole
        let shots: [Shot]
        let penaltyStrokes: Int
    }

    @MainActor
    static func build(holes: [HoleInput], course: CuratedCourse?,
                      localAnchors: [Int: LocalCourseAnchor] = [:]) -> ScorecardModel {
        let byNumber = Dictionary(holes.map { ($0.hole.holeNumber, $0) }, uniquingKeysWith: { a, _ in a })
        let columns = (1...18).map { number -> ScorecardColumn in
            let curated = course?.holes.first { $0.number == number }
            let input = byNumber[number]
            let par = input?.hole.par ?? curated?.par
            let confirmed = input?.hole.confirmedAt != nil
            let shots = input?.shots ?? []
            let pens = input?.penaltyStrokes ?? 0
            return ScorecardColumn(
                number: number,
                yards: yards(curated: curated, local: localAnchors[number]),
                par: par,
                strokeIndex: curated?.strokeIndex,
                score: confirmed ? shots.count + pens : nil,
                putts: confirmed ? shots.filter(\.isPutt).count : nil,
                gir: confirmed ? greenInRegulation(shots: shots, par: par) : nil,
                penalties: confirmed ? pens : nil,
                story: input.map { story(shots: $0.shots, penalties: $0.penaltyStrokes) },
                holeID: input?.hole.id,
                isConfirmed: confirmed
            )
        }
        let hasSI = course?.holes.contains { $0.strokeIndex != nil } ?? false
        return ScorecardModel(columns: columns, hasStrokeIndex: hasSI)
    }

    /// Course yardage, else tee→green from the anchors (local wins), else nil.
    private static func yards(curated: CuratedHole?, local: LocalCourseAnchor?) -> Int? {
        if let y = curated?.yards { return Int(y.rounded()) }
        guard let tee = local?.tee ?? curated?.teeAnchor,
              let green = local?.green ?? curated?.greenAnchor else { return nil }
        let meters = Distance.meters(from: tee.coordinate, to: green.coordinate)
        return Int(Distance.yards(fromMeters: meters).rounded())
    }

    @MainActor
    static func story(shots: [Shot], penalties: Int) -> String {
        let ordered = shots.sorted { $0.sequenceNumber < $1.sequenceNumber }
        let full = ordered.filter { !$0.isPutt }
            .map { ClubCatalog.shared.shortName(id: $0.club) ?? "?" }
        let putts = ordered.filter(\.isPutt).count
        var parts = full
        if putts > 0 { parts.append("\(putts) putt\(putts == 1 ? "" : "s")") }
        if penalties > 0 { parts.append("\(penalties) pen") }
        return parts.isEmpty ? "No shots logged" : parts.joined(separator: " · ")
    }
}
