import CoreLocation
import Foundation

/// One hole as the course preview shows it: the card (par, yards, stroke
/// index) and the anchors the map draws (a local capture wins over curated,
/// as everywhere else).
struct CoursePreviewHole: Equatable {
    let number: Int
    let par: Int?
    /// Card yards, else tee → green from the anchors; nil without either.
    let yards: Int?
    let strokeIndex: Int?
    let tee: GeoPoint?
    let green: GeoPoint?
}

/// Pure rules behind `CoursePreviewScreen` — look through a course's holes
/// without starting a round. Nothing here touches the database.
enum CoursePreview {
    static func holes(course: CuratedCourse, local: [LocalCourseAnchor]) -> [CoursePreviewHole] {
        course.holes
            .sorted { $0.number < $1.number }
            .map { curated in
                let captured = local.first { $0.holeNumber == curated.number }
                let tee = captured?.tee ?? curated.teeAnchor
                let green = captured?.green ?? curated.greenAnchor
                return CoursePreviewHole(number: curated.number, par: curated.par,
                                         yards: curated.yards.map { Int($0.rounded()) } ?? length(tee, green),
                                         strokeIndex: curated.strokeIndex, tee: tee, green: green)
            }
    }

    private static func length(_ tee: GeoPoint?, _ green: GeoPoint?) -> Int? {
        guard let tee, let green else { return nil }
        let meters = Distance.meters(from: tee.coordinate, to: green.coordinate)
        return Int(Distance.yards(fromMeters: meters).rounded())
    }

    // MARK: Paging (wraps, so a nine goes 9 → 1)

    static func next(after number: Int, in holes: [CoursePreviewHole]) -> Int? {
        step(from: number, by: 1, in: holes)
    }

    static func previous(before number: Int, in holes: [CoursePreviewHole]) -> Int? {
        step(from: number, by: -1, in: holes)
    }

    private static func step(from number: Int, by delta: Int, in holes: [CoursePreviewHole]) -> Int? {
        let numbers = holes.map(\.number)
        guard !numbers.isEmpty else { return nil }
        guard let index = numbers.firstIndex(of: number) else { return numbers.first }
        return numbers[(index + delta + numbers.count) % numbers.count]
    }

    // MARK: Text

    /// "PAR 4 · 281 YD · SI 18"; parts without data are left out.
    static func caption(_ hole: CoursePreviewHole, units: Units) -> String {
        var parts = ["PAR \(hole.par.map(String.init) ?? "—")"]
        if let yards = hole.yards {
            let shown = units.format(yards: yards)
            parts.append("\(shown.value) \(shown.unit.uppercased())")
        }
        if let index = hole.strokeIndex { parts.append("SI \(index)") }
        return parts.joined(separator: " · ")
    }

    /// "18 HOLES · PAR 70 · 6,160 YD" (par and length only when every hole has one).
    static func courseCaption(_ holes: [CoursePreviewHole], units: Units) -> String {
        var parts = ["\(holes.count) HOLES"]
        let pars = holes.compactMap(\.par)
        if !holes.isEmpty, pars.count == holes.count { parts.append("PAR \(pars.reduce(0, +))") }
        let yards = holes.compactMap(\.yards)
        if !holes.isEmpty, yards.count == holes.count {
            let shown = units.format(yards: yards.reduce(0, +))
            parts.append("\(shown.value.formatted(.number.grouping(.automatic))) \(shown.unit.uppercased())")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Map

    /// The course map's lines and badges: tee → green, the par, no score.
    static func outlines(_ holes: [CoursePreviewHole]) -> [CourseHoleOutline] {
        holes.compactMap { hole in
            guard hole.tee != nil || hole.green != nil else { return nil }
            return CourseHoleOutline(number: hole.number, tee: hole.tee?.coordinate,
                                     green: hole.green?.coordinate, par: hole.par)
        }
    }

    /// A stable id per (course, hole) for `HoleMap.holeID`: a change of id is
    /// what re-frames the map, and the preview has no `Hole` rows.
    static func mapID(course: String, hole: Int) -> UUID {
        // FNV-1a: stable across launches (Swift's `Hasher` is seeded per process).
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(course)|\(hole)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { bytes[i] = UInt8(truncatingIfNeeded: hash >> (8 * UInt64(i))) }
        bytes[8] = UInt8(truncatingIfNeeded: hole)
        let tuple = (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                     bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: tuple)
    }
}

/// Home → course preview navigation value.
struct CoursePreviewRoute: Hashable, Identifiable {
    let course: CuratedCourse
    let holes: [CoursePreviewHole]
    /// Open straight on this hole (DEBUG screenshots); nil = the whole course.
    var initialHole: Int? = nil

    var id: String { course.id }

    static func == (lhs: CoursePreviewRoute, rhs: CoursePreviewRoute) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
