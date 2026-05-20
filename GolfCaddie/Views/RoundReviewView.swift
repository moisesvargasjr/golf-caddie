import SwiftUI

struct RoundReviewView: View {
    // @State (not let) so a retro-link "Set course" can mutate
    // round.curatedCourseId in place and the downstream NavigationLink picks
    // up the new value the next time the user opens the hole editor.
    @State private var round: Round
    let bag: [ClubID]
    let onResume: (() -> Void)?
    let onDismiss: (() -> Void)?

    @State private var holes: [Hole] = []
    @State private var shotsByHole: [UUID: [Shot]] = [:]
    @State private var penaltiesByHole: [UUID: [Penalty]] = [:]
    @State private var curatedName: String?
    @State private var curatedCourses: [CuratedCourse] = []
    @State private var showCoursePicker = false
    @State private var loadError: String?

    init(
        round: Round,
        bag: [ClubID],
        onResume: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        _round = State(initialValue: round)
        self.bag = bag
        self.onResume = onResume
        self.onDismiss = onDismiss
    }

    var body: some View {
        List {
            summarySection
            courseLinkSection
            if onResume != nil, round.endedAt != nil {
                resumeSection
            }
            if !holes.isEmpty {
                Section {
                    NavigationLink {
                        HoleDetailView(
                            holes: holes,
                            bag: bag,
                            curatedCourseId: round.curatedCourseId,
                            onChanged: { reload() }
                        )
                    } label: {
                        Label("Review & Edit Holes", systemImage: "pencil.and.list.clipboard")
                    }
                }
                scorecardSection
                shotsSection
            } else {
                Section {
                    Text("No holes recorded for this round.")
                        .foregroundStyle(.secondary)
                }
            }
            if let loadError {
                Section {
                    Text(loadError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle(roundTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onDismiss {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDismiss)
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showCoursePicker) {
            CoursePickerSheet(
                courses: curatedCourses,
                current: round.curatedCourseId,
                onPick: { id in setCurated(id) },
                onCancel: { showCoursePicker = false }
            )
        }
        .onAppear { reload() }
    }

    private var courseLinkSection: some View {
        Section {
            Button {
                showCoursePicker = true
            } label: {
                HStack {
                    Text("Course")
                    Spacer()
                    if let curatedName {
                        Text(curatedName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Set course")
                            .foregroundStyle(.tint)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        } footer: {
            if curatedName == nil {
                Text("Link this round to a curated course to enable green-anchor capture and distance-to-green.")
            }
        }
    }

    private func setCurated(_ id: String?) {
        do {
            try RoundRepository.setCuratedCourseId(roundID: round.id, id: id)
            round.curatedCourseId = id
            showCoursePicker = false
            reload()
        } catch {
            loadError = "Couldn't set course: \(error.localizedDescription)"
        }
    }

    private var roundTitle: String {
        if let course = round.courseName, !course.isEmpty {
            return course
        }
        return round.startedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var totalShots: Int {
        shotsByHole.values.reduce(0) { $0 + $1.count }
    }

    private var totalPenaltyStrokes: Int {
        penaltiesByHole.values.reduce(0) { acc, list in
            acc + list.reduce(0) { $0 + $1.strokeCount }
        }
    }

    private var totalScore: Int {
        totalShots + totalPenaltyStrokes
    }

    private var totalPar: Int? {
        let pars = holes.compactMap { $0.par }
        guard pars.count == holes.count, !holes.isEmpty else { return nil }
        return pars.reduce(0, +)
    }

    private var scoreVsPar: String? {
        guard let par = totalPar else { return nil }
        let diff = totalScore - par
        if diff == 0 { return "E" }
        if diff > 0 { return "+\(diff)" }
        return "\(diff)"
    }

    private var resumeSection: some View {
        Section {
            Button {
                onResume?()
            } label: {
                Label("Resume Round", systemImage: "play.circle.fill")
                    .foregroundStyle(.green)
            }
        } footer: {
            Text("If you ended the round by mistake, tap to reopen it. Tracking will resume on the last hole.")
        }
    }

    private var summarySection: some View {
        Section("Summary") {
            LabeledContent("Holes Played") { Text("\(holes.count)").monospacedDigit() }
            LabeledContent("Total Shots") { Text("\(totalShots)").monospacedDigit() }
            if totalPenaltyStrokes > 0 {
                LabeledContent("Penalties") { Text("+\(totalPenaltyStrokes)").monospacedDigit() }
            }
            LabeledContent("Score") {
                HStack(spacing: 6) {
                    Text("\(totalScore)")
                        .font(.headline)
                        .monospacedDigit()
                    if let label = scoreVsPar {
                        Text("(\(label))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let endedAt = round.endedAt {
                LabeledContent("Duration") {
                    Text(formatDuration(endedAt.timeIntervalSince(round.startedAt)))
                }
            }
        }
    }

    private var scorecardSection: some View {
        Section("Scorecard") {
            HStack {
                Text("Hole").font(.caption.bold()).foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                Spacer()
                Text("Par").font(.caption.bold()).foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .center)
                Text("Shots").font(.caption.bold()).foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .center)
                Text("Score").font(.caption.bold()).foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }
            ForEach(holes) { hole in
                HoleRowSummary(
                    hole: hole,
                    shotCount: shotsByHole[hole.id]?.count ?? 0,
                    penaltyStrokes: (penaltiesByHole[hole.id] ?? []).reduce(0) { $0 + $1.strokeCount }
                )
            }
        }
    }

    private var shotsSection: some View {
        Section("Shots") {
            ForEach(holes) { hole in
                if let shots = shotsByHole[hole.id], !shots.isEmpty {
                    ForEach(shots) { shot in
                        NavigationLink {
                            ShotEditView(
                                shot: shot,
                                bag: bag,
                                onDelete: { deleteShot(shot) }
                            )
                        } label: {
                            ShotRowSummary(shot: shot, hole: hole)
                        }
                    }
                }
            }
        }
    }

    private func reload() {
        do {
            let allHoles = try HoleRepository.holesForRound(round.id)
            holes = trimTrailingEmptyHole(allHoles)

            var shotsMap: [UUID: [Shot]] = [:]
            var penaltiesMap: [UUID: [Penalty]] = [:]
            for hole in holes {
                shotsMap[hole.id] = try ShotRepository.shotsForHole(hole.id)
                penaltiesMap[hole.id] = try PenaltyRepository.penaltiesForHole(hole.id)
            }
            shotsByHole = shotsMap
            penaltiesByHole = penaltiesMap
            // Curated catalog + the round's linked course name (if any) for
            // the courseLinkSection. Both soft-fail (empty / nil) — the
            // section degrades to "Set course" when the cache is empty too.
            curatedCourses = (try? CourseDataRepository.allCourses()) ?? []
            if let cid = round.curatedCourseId {
                curatedName = curatedCourses.first { $0.id == cid }?.name
            } else {
                curatedName = nil
            }
            loadError = nil
        } catch {
            loadError = "Failed to load: \(error.localizedDescription)"
        }
    }

    private func trimTrailingEmptyHole(_ allHoles: [Hole]) -> [Hole] {
        guard let last = allHoles.last, last.confirmedAt == nil else { return allHoles }
        let lastShots = (try? ShotRepository.count(forHole: last.id)) ?? 0
        let lastPenalties = (try? PenaltyRepository.penaltiesForHole(last.id).count) ?? 0
        if lastShots == 0 && lastPenalties == 0 {
            return Array(allHoles.dropLast())
        }
        return allHoles
    }

    private func deleteShot(_ shot: Shot) {
        do {
            try ShotRepository.delete(shot)
            reload()
        } catch {
            loadError = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

private struct HoleRowSummary: View {
    let hole: Hole
    let shotCount: Int
    let penaltyStrokes: Int

    private var score: Int { shotCount + penaltyStrokes }

    private var diff: Int? {
        guard let par = hole.par else { return nil }
        return score - par
    }

    private var diffColor: Color {
        guard let diff else { return .secondary }
        if diff < 0 { return .green }
        if diff == 0 { return .primary }
        return .orange
    }

    var body: some View {
        HStack {
            Text("\(hole.holeNumber)")
                .frame(width: 60, alignment: .leading)
                .monospacedDigit()
            Spacer()
            Text(hole.par.map(String.init) ?? "—")
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .center)
                .monospacedDigit()
            HStack(spacing: 2) {
                Text("\(shotCount)")
                if penaltyStrokes > 0 {
                    Text("+\(penaltyStrokes)")
                        .foregroundStyle(.orange)
                }
            }
            .frame(width: 60, alignment: .center)
            .monospacedDigit()
            .font(.caption)
            Text("\(score)")
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(diffColor)
                .frame(width: 50, alignment: .trailing)
        }
    }
}

private struct ShotRowSummary: View {
    let shot: Shot
    let hole: Hole

    var body: some View {
        HStack(spacing: 10) {
            Text("H\(hole.holeNumber)·\(shot.sequenceNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 56, alignment: .leading)
            Text(shot.club?.longName ?? "(no club)")
                .foregroundStyle(shot.club == nil ? .orange : .primary)
                .lineLimit(1)
            Spacer()
            metadataView
        }
    }

    @ViewBuilder
    private var metadataView: some View {
        if !shot.hadGPS {
            Text("manual")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if let acc = shot.gpsAccuracy {
            Text(String(format: "±%.0fm", acc))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

/// Sheet to retro-link a round to a curated course. Lists the on-device
/// curated catalog; tap to pick, or "Unlink" to clear. Empty-catalog state
/// nudges to sync.
private struct CoursePickerSheet: View {
    let courses: [CuratedCourse]
    let current: String?
    let onPick: (String?) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if courses.isEmpty {
                    Section {
                        Text("No curated courses on this device yet. Open the app online to sync.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(courses) { course in
                            Button {
                                onPick(course.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(course.name)
                                            .foregroundStyle(.primary)
                                        if let firstAlias = course.aliases.first {
                                            Text(firstAlias)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if course.id == current {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if current != nil {
                    Section {
                        Button(role: .destructive) {
                            onPick(nil)
                        } label: {
                            Label("Unlink (no course)", systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .navigationTitle("Set course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}
