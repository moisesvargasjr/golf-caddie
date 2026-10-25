import SwiftUI

/// The scorecard as ONE full-screen presentation (live CARD and finished
/// rounds). Measures its own window (`adaptiveLayoutRoot`), so a fold/unfold
/// while it's open swaps the card variant instead of dismissing it.
struct AdaptiveScorecardPresentation: View {
    let round: Round
    /// The live hole; nil for a finished round.
    let currentHoleNumber: Int?
    let curatedCourseId: String?
    var live: LiveHoleEditing? = nil
    var onOpenHole: ((Int) -> Void)? = nil
    var onOpenCourseMap: (() -> Void)? = nil
    let onDismiss: () -> Void

    var body: some View {
        ScorecardScreen(round: round, currentHoleNumber: currentHoleNumber,
                        curatedCourseId: curatedCourseId, live: live, onDismiss: onDismiss,
                        onOpenHole: onOpenHole, onOpenCourseMap: onOpenCourseMap)
            .adaptiveLayoutRoot()
            .themedRoot()
    }
}

/// Memoizes curated-course decoding for the in-round view, which looks the
/// course up several times per render (yardage, bearing, anchors). Entries
/// expire so a catalog sync mid-round is picked up within a minute.
@MainActor
final class CourseLookupCache {
    static let shared = CourseLookupCache()
    private var entries: [String: (course: CuratedCourse?, at: Date)] = [:]
    private let ttl: TimeInterval = 60

    func course(_ id: String) -> CuratedCourse? {
        if let hit = entries[id], Date().timeIntervalSince(hit.at) < ttl { return hit.course }
        let course = try? CourseDataRepository.course(byId: id)
        entries[id] = (course ?? nil, Date())
        return course ?? nil
    }

    func invalidate() { entries = [:] }
}
