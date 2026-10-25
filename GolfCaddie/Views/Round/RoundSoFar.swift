import Foundation

// The casual screen's "Your round": every scored hole, newest first, with the
// round's to-par running total and a marker on the hole on screen. Pure, so
// it is unit tested (RoundSoFarTests); `RoundScoresList` draws it as a list
// (open Duo, landscape), chips (iPhone portrait) or squares (folded).

/// One scored hole, as the screen reads it from the store.
struct RoundScoreInput: Equatable, Sendable {
    let holeNumber: Int
    let par: Int?
    /// Gross strokes (hand score, or shots + penalty strokes).
    let strokes: Int
    let putts: Int?
}

/// The scorecard mark around a score: circled under par, boxed over par.
enum ScoreShape: Equatable, Sendable {
    case plain
    case circle
    case square
}

struct RoundScoreRow: Identifiable, Equatable, Sendable {
    let holeNumber: Int
    let par: Int?
    let strokes: Int
    let putts: Int?
    /// Strokes against par; nil without a par.
    let toPar: Int?
    /// The round to par through this hole, in the order played.
    let runningToPar: Int
    /// The hole on screen (a past hole opened from the list to edit).
    let isOnScreen: Bool

    var id: Int { holeNumber }

    var shape: ScoreShape {
        guard let toPar, toPar != 0 else { return .plain }
        return toPar < 0 ? .circle : .square
    }

    /// "PAR 4" / "PAR —".
    var parText: String { par.map { "PAR \($0)" } ?? "PAR —" }

    /// "+1", "E", "-1"; "—" without a par.
    var toParText: String { toPar.map(RoundMapFormat.toPar) ?? "—" }

    /// "+1 · 2P" (the list's right column).
    var detailText: String {
        guard let putts else { return toParText }
        return "\(toParText) · \(putts)P"
    }

    /// "Hole 7, par 4, scored 5, bogey, 2 putts".
    var accessibilityLabel: String {
        var parts = ["Hole \(holeNumber)"]
        if let par { parts.append("par \(par)") }
        parts.append("scored \(strokes)")
        if let toPar { parts.append(ScoreNaming.spoken(strokes: strokes, toPar: toPar)) }
        if let putts { parts.append("\(putts) \(putts == 1 ? "putt" : "putts")") }
        return parts.joined(separator: ", ")
    }
}

struct RoundSoFar: Equatable, Sendable {
    /// Scored holes, newest (last played) first.
    let rows: [RoundScoreRow]
    let totalStrokes: Int
    /// Over the holes with a par.
    let toPar: Int
    /// Holes scored.
    let thru: Int
    /// The live round's current hole; nil for a finished round.
    let liveHoleNumber: Int?

    static let empty = RoundSoFar(rows: [], totalStrokes: 0, toPar: 0, thru: 0, liveHoleNumber: nil)

    var isEmpty: Bool { rows.isEmpty }

    /// "31 · +4 THRU 7" (list header).
    var headerText: String {
        isEmpty ? "NO HOLES SCORED" : "\(totalStrokes) · \(RoundMapFormat.toPar(toPar)) THRU \(thru)"
    }

    /// "+4 THRU 7" (folded box, iPhone row).
    var shortText: String {
        isEmpty ? "NO HOLES YET" : "\(RoundMapFormat.toPar(toPar)) THRU \(thru)"
    }

    /// `startingHole` orders the holes as played (a back-nine start plays
    /// 10…18 then 1…9; holes before a late start entered afterwards come
    /// after 18). `onScreen` marks a past hole opened to edit; the live hole
    /// on screen marks nothing (it isn't in the list until it is scored).
    static func build(scores: [RoundScoreInput], startingHole: Int?, onScreen: Int?,
                      live: Int?) -> RoundSoFar {
        let start = startingHole ?? HoleScoring.holeRange.lowerBound
        let count = HoleScoring.holeRange.upperBound
        func playOrder(_ hole: Int) -> Int { ((hole - start) % count + count) % count }

        var seen: Set<Int> = []
        let unique = scores.filter { seen.insert($0.holeNumber).inserted }
        let played = unique.sorted { playOrder($0.holeNumber) < playOrder($1.holeNumber) }

        var running = 0
        let oldestFirst: [RoundScoreRow] = played.map { score in
            let diff = score.par.map { score.strokes - $0 }
            running += diff ?? 0
            return RoundScoreRow(holeNumber: score.holeNumber, par: score.par, strokes: score.strokes,
                                 putts: score.putts, toPar: diff, runningToPar: running,
                                 isOnScreen: score.holeNumber == onScreen && onScreen != live)
        }
        return RoundSoFar(rows: oldestFirst.reversed(),
                          totalStrokes: played.reduce(0) { $0 + $1.strokes },
                          toPar: running,
                          thru: played.count,
                          liveHoleNumber: live)
    }
}

/// Golf names for a score against par.
enum ScoreNaming {
    /// Spoken (VoiceOver): "bogey", "double bogey", "3 over par", "hole in one".
    static func spoken(strokes: Int, toPar: Int) -> String {
        if strokes == 1 { return "hole in one" }
        switch toPar {
        case -2: return "eagle"
        case -1: return "birdie"
        case 0: return "par"
        case 1: return "bogey"
        case 2: return "double bogey"
        case 3: return "triple bogey"
        default: return toPar > 0 ? "\(toPar) over par" : "\(-toPar) under par"
        }
    }

    /// Under a grid cell, as on the canvas: EAGLE … TRIPLE; ACE for a 1.
    static func stamp(strokes: Int, par: Int?) -> String {
        guard let par else { return "" }
        if strokes == 1 { return "ACE" }
        switch strokes - par {
        case -2: return "EAGLE"
        case -1: return "BIRDIE"
        case 0: return "PAR"
        case 1: return "BOGEY"
        case 2: return "DOUBLE"
        case 3: return "TRIPLE"
        default: return ""
        }
    }
}
