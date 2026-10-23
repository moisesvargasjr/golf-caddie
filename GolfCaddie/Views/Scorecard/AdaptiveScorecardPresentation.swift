import SwiftUI

/// The in-round scorecard as ONE presentation whose body follows the width:
/// the physical card when expanded, the compact card otherwise. Measures its
/// own window (`adaptiveLayoutRoot`), so a fold/unfold while it's open swaps
/// the body instead of dismissing the presentation.
struct AdaptiveScorecardPresentation: View {
    let round: Round
    let currentHoleNumber: Int
    let bag: [Club]
    let curatedCourseId: String?
    let onStrokeMoved: (Set<UUID>) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ScorecardBody(round: round, currentHoleNumber: currentHoleNumber, bag: bag,
                      curatedCourseId: curatedCourseId, onStrokeMoved: onStrokeMoved,
                      onDismiss: onDismiss)
            .adaptiveLayoutRoot()
            .themedRoot()
    }
}

private struct ScorecardBody: View {
    let round: Round
    let currentHoleNumber: Int
    let bag: [Club]
    let curatedCourseId: String?
    let onStrokeMoved: (Set<UUID>) -> Void
    let onDismiss: () -> Void
    @Environment(\.layoutClass) private var layoutClass

    var body: some View {
        if layoutClass == .expanded {
            PhysicalScorecardView(round: round, currentHoleNumber: currentHoleNumber, bag: bag,
                                  curatedCourseId: curatedCourseId, onDismiss: onDismiss)
        } else {
            InRoundScorecardSheet(round: round, currentHoleNumber: currentHoleNumber, bag: bag,
                                  curatedCourseId: curatedCourseId, onStrokeMoved: onStrokeMoved,
                                  onDismiss: onDismiss)
        }
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
