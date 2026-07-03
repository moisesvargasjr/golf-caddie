import SwiftUI

/// "Official Card" — round summary screen. Reads like a paper scorecard:
/// masthead with course name, big final score, front-nine / back-nine tables
/// with shape-badge cells per hole, a legend, and a signature line.
///
/// Below the card sit the operational sections from the previous design that
/// the prototype didn't cover: curated-course linking, resume-round (if the
/// caller passed `onResume`), and per-hole edit (now reached by tapping a
/// score cell). The flat all-shots list is gone — shots are edited from
/// inside `HoleDetailView`.
struct RoundReviewView: View {
    // @State (not let) so a retro-link "Set course" can mutate
    // round.curatedCourseId in place and the downstream NavigationLink picks
    // up the new value the next time the user opens the hole editor.
    @State private var round: Round
    let bag: [ClubID]
    let onResume: (() -> Void)?
    let onDismiss: (() -> Void)?
    /// Called after the round is successfully deleted. Callers should refresh
    /// their list and may pop this view (we already `dismiss()` internally).
    let onDeleted: (() -> Void)?

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var holes: [Hole] = []
    @State private var shotsByHole: [UUID: [Shot]] = [:]
    @State private var penaltiesByHole: [UUID: [Penalty]] = [:]
    @State private var curatedName: String?
    @State private var curatedCourses: [CuratedCourse] = []
    @State private var showCoursePicker = false
    @State private var loadError: String?
    @State private var roundOrdinal: Int = 0
    @State private var showDeleteConfirm: Bool = false

    init(
        round: Round,
        bag: [ClubID],
        onResume: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        onDeleted: (() -> Void)? = nil
    ) {
        _round = State(initialValue: round)
        self.bag = bag
        self.onResume = onResume
        self.onDismiss = onDismiss
        self.onDeleted = onDeleted
    }

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    navRow
                        .padding(.horizontal, 24)
                        .padding(.top, 6)

                    masthead
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                    DoubleRule()
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                    bigScoreBlock
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                    SingleRule(weight: .hairline, opacity: 0.5)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                    if !holes.isEmpty {
                        scorecardTables
                            .padding(.horizontal, 20)
                            .padding(.top, 16)

                        legendStrip
                            .padding(.horizontal, 24)
                            .padding(.top, 16)

                        signatureLine
                            .padding(.horizontal, 24)
                            .padding(.top, 28)

                        editHolesLink
                            .padding(.horizontal, 24)
                            .padding(.top, 28)
                    } else {
                        Text("NO HOLES RECORDED FOR THIS ROUND")
                            .font(AppFont.stamp)
                            .tracking(1.4)
                            .foregroundStyle(palette.ink3)
                            .padding(.horizontal, 24)
                            .padding(.top, 24)
                    }

                    courseLinkSection
                        .padding(.horizontal, 24)
                        .padding(.top, 28)

                    if onResume != nil, round.endedAt != nil {
                        resumeSection
                            .padding(.horizontal, 24)
                            .padding(.top, 20)
                    }

                    if round.endedAt != nil {
                        deleteSection
                            .padding(.horizontal, 24)
                            .padding(.top, 32)
                    }

                    if let loadError {
                        Text(loadError)
                            .font(AppFont.micro)
                            .tracking(1.2)
                            .foregroundStyle(palette.red)
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                    }

                    Spacer(minLength: 48)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showCoursePicker) {
            CoursePickerSheet(
                courses: curatedCourses,
                current: round.curatedCourseId,
                onPick: { id in setCurated(id) },
                onCancel: { showCoursePicker = false },
                onRefresh: {
                    // B29: pull-to-refresh bypasses the hourly catalog throttle.
                    await CourseSyncClient.shared.syncIfStale(force: true)
                    let fresh = await CourseDataRepository.allCoursesFromAsyncContext()
                    curatedCourses = fresh
                    return fresh
                }
            )
        }
        .alert("Delete this round?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { performDelete() }
        } message: {
            let course = (round.courseName?.isEmpty == false) ? round.courseName! : "This round"
            Text("\(course) and all its holes, shots, and penalties will be permanently deleted.")
        }
        .onAppear { reload() }
    }

    // MARK: - Nav row

    private var navRow: some View {
        HStack {
            Button {
                if let onDismiss { onDismiss() } else { dismiss() }
            } label: {
                Text(onDismiss != nil ? "‹ DONE" : "‹ BACK")
                    .font(AppFont.metadata)
                    .tracking(1.4)
                    .foregroundStyle(palette.ink)
            }
            Spacer()
            // SHARE — placeholder; not wired
            Text("SHARE")
                .font(AppFont.metadata)
                .tracking(1.4)
                .foregroundStyle(palette.ink3)
        }
    }

    // MARK: - Masthead

    private var masthead: some View {
        VStack(spacing: 12) {
            Stamp(text: "Official Card · No. \(roundOrdinal)", color: palette.red)

            Text(courseDisplay.primary)
                .font(AppFont.courseName)
                .tracking(-1.2)
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)

            if let secondary = courseDisplay.secondary {
                Text(secondary)
                    .font(.custom(AppFont.serifName, size: 22).weight(.regular).italic())
                    .tracking(-0.4)
                    .foregroundStyle(palette.ink2)
            }

            Text(dateLineDisplay)
                .font(AppFont.stamp)
                .tracking(1.4)
                .foregroundStyle(palette.ink2)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var courseDisplay: (primary: String, secondary: String?) {
        guard let name = round.courseName, !name.isEmpty else {
            return ("Untitled Round", nil)
        }
        // Try to split "<name> Golf Course" / "<name> G.C." etc.
        let suffixes = [" Golf Course", " G.C.", " Golf Club"]
        for suffix in suffixes {
            if let range = name.range(of: suffix, options: [.caseInsensitive, .anchored, .backwards]) {
                let primary = String(name[..<range.lowerBound])
                return (primary, "Golf Course")
            }
        }
        return (name, nil)
    }

    private var dateLineDisplay: String {
        let f = DateFormatter()
        f.dateFormat = "MMM · d · yyyy"
        return f.string(from: round.startedAt).uppercased()
    }

    // MARK: - Big score block

    private var bigScoreBlock: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FINAL · \(holes.count) HOLES")
                    .font(AppFont.stamp)
                    .tracking(1.4)
                    .foregroundStyle(palette.ink3)
                Text("\(totalScore)")
                    .font(AppFont.scoreHero)
                    .tracking(-4.5)
                    .lineSpacing(-30)  // approximates lineHeight 0.85
                    .foregroundStyle(palette.ink)
                    .tabularNumerals()
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                if let scoreVsPar {
                    Stamp(text: scoreVsPar, color: palette.red, size: .md)
                }
                Text(durationAndShotsLine)
                    .font(AppFont.metadata)
                    .tracking(1.2)
                    .foregroundStyle(palette.ink2)
                    .tabularNumerals()
            }
            .padding(.bottom, 18)
        }
    }

    private var durationAndShotsLine: String {
        var parts: [String] = []
        if let endedAt = round.endedAt {
            parts.append(formatDuration(endedAt.timeIntervalSince(round.startedAt)))
        }
        parts.append("\(totalShots) SHOTS")
        return parts.joined(separator: " · ")
    }

    // MARK: - Scorecard

    private var scorecardTables: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Only render a nine that actually has holes, so a back-9-only (or
            // front-9-only) round doesn't show an empty table.
            if holes.contains(where: { $0.holeNumber <= 9 }) {
                scorecardTable(title: "Front nine.", range: 1...9)
            }
            if holes.contains(where: { $0.holeNumber >= 10 }) {
                scorecardTable(title: "Back nine.", range: 10...18)
            }
        }
    }

    private func scorecardTable(title: String, range: ClosedRange<Int>) -> some View {
        let rowHoles = holes.filter { range.contains($0.holeNumber) }
        let rowPar = rowHoles.reduce(0) { $0 + ($1.par ?? 0) }
        let rowShots = rowHoles.reduce(0) { $0 + holeScore($1) }
        let rowDelta = rowShots - rowPar
        let isFront = range.lowerBound == 1
        let summaryLabel = isFront ? "OUT" : "IN"

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(palette.ink)
                Spacer()
                Text("\(summaryLabel) \(rowShots) · \(deltaString(rowDelta))")
                    .font(AppFont.metadata)
                    .tracking(1.2)
                    .foregroundStyle(palette.ink2)
                    .tabularNumerals()
            }

            VStack(spacing: 0) {
                tableHeaderRow(range: range, label: summaryLabel)
                tableParRow(range: range, total: rowPar)
                tableYouRow(range: range, total: rowShots, totalIsRed: rowDelta > 0)
            }
        }
    }

    private func tableHeaderRow(range: ClosedRange<Int>, label: String) -> some View {
        HStack(spacing: 0) {
            cell(text: "HOLE", style: .header, align: .leading)
            ForEach(Array(range), id: \.self) { n in
                cell(text: "\(n)", style: .header, align: .center)
            }
            cell(text: label, style: .header, align: .trailing)
        }
        .overlay(alignment: .top) { Rectangle().fill(palette.ink).frame(height: 2) }
        .overlay(alignment: .bottom) { Rectangle().fill(palette.ink).frame(height: 1) }
    }

    private func tableParRow(range: ClosedRange<Int>, total: Int) -> some View {
        HStack(spacing: 0) {
            cell(text: "PAR", style: .label, align: .leading)
            ForEach(Array(range), id: \.self) { n in
                if let hole = holes.first(where: { $0.holeNumber == n }), let par = hole.par {
                    cell(text: "\(par)", style: .label, align: .center)
                } else {
                    cell(text: "—", style: .label, align: .center)
                }
            }
            cell(text: "\(total)", style: .label, align: .trailing)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
    }

    private func tableYouRow(range: ClosedRange<Int>, total: Int, totalIsRed: Bool) -> some View {
        HStack(spacing: 0) {
            cell(text: "YOU", style: .label, align: .leading)
            ForEach(Array(range), id: \.self) { n in
                if let hole = holes.first(where: { $0.holeNumber == n }), let par = hole.par {
                    let score = holeScore(hole)
                    NavigationLink {
                        HoleDetailView(
                            holes: holes,
                            bag: bag,
                            curatedCourseId: round.curatedCourseId,
                            startIndex: holes.firstIndex(where: { $0.id == hole.id }) ?? 0,
                            onChanged: { reload() }
                        )
                    } label: {
                        ScoreBadge(score: score, par: par)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("—")
                        .font(.custom(AppFont.monoName, size: 13).weight(.bold))
                        .foregroundStyle(palette.ink3)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                }
            }
            Text("\(total)")
                .font(.custom(AppFont.monoName, size: 16).weight(.bold))
                .foregroundStyle(totalIsRed ? palette.red : palette.ink)
                .tabularNumerals()
                .frame(width: 44, alignment: .trailing)
        }
    }

    private enum CellStyle { case header, label }

    private func cell(text: String, style: CellStyle, align: Alignment) -> some View {
        Group {
            switch style {
            case .header:
                Text(text)
                    .font(AppFont.micro)
                    .tracking(1.4)
                    .foregroundStyle(palette.ink2)
            case .label:
                Text(text)
                    .font(.custom(AppFont.monoName, size: 11).weight(.bold))
                    .foregroundStyle(palette.ink2)
                    .tabularNumerals()
            }
        }
        .frame(maxWidth: .infinity, alignment: align)
        .frame(width: align == .leading || align == .trailing ? 44 : nil)
        .padding(.vertical, 7)
    }

    private var legendStrip: some View {
        HStack(spacing: 16) {
            legendItem(shape: .circle, label: "BIRDIE")
            legendItem(shape: .square, label: "BOGEY")
            legendItem(shape: .squareRed, label: "DOUBLE+")
            Spacer()
        }
    }

    private enum LegendShape { case circle, square, squareRed }

    private func legendItem(shape: LegendShape, label: String) -> some View {
        HStack(spacing: 6) {
            Group {
                switch shape {
                case .circle:
                    Circle().stroke(palette.red, lineWidth: 1.5).frame(width: 12, height: 12)
                case .square:
                    RoundedRectangle(cornerRadius: 2).stroke(palette.ink, lineWidth: 1.5).frame(width: 12, height: 12)
                case .squareRed:
                    RoundedRectangle(cornerRadius: 2).stroke(palette.red, lineWidth: 1.5).frame(width: 12, height: 12)
                }
            }
            Text(label)
                .font(AppFont.stamp)
                .tracking(1.2)
                .foregroundStyle(palette.ink2)
        }
    }

    // MARK: - Signature

    private var signatureLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottom) {
                Rectangle().fill(palette.ink).frame(height: 1)
                Text("—")
                    .font(.custom(AppFont.serifName, size: 22).italic())
                    .foregroundStyle(palette.ink2)
                    .padding(.bottom, 2)
                    .padding(.leading, 8)
            }
            .frame(height: 28)
            Text("SIGNED · PLAYER")
                .font(AppFont.stamp)
                .tracking(1.4)
                .foregroundStyle(palette.ink3)
        }
    }

    // MARK: - Operational sections (re-skinned existing functionality)

    private var editHolesLink: some View {
        NavigationLink {
            HoleDetailView(
                holes: holes,
                bag: bag,
                curatedCourseId: round.curatedCourseId,
                startIndex: 0,
                onChanged: { reload() }
            )
        } label: {
            HStack {
                Stamp(text: "Review & Edit Holes")
                Spacer()
                Text("›")
                    .font(AppFont.metadata)
                    .foregroundStyle(palette.ink2)
            }
        }
        .buttonStyle(.plain)
    }

    private var courseLinkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("COURSE")
                    .font(AppFont.stamp)
                    .tracking(1.4)
                    .foregroundStyle(palette.ink3)
                Spacer()
                Rectangle().fill(palette.rule).frame(height: 1)
            }
            Button {
                showCoursePicker = true
            } label: {
                HStack {
                    Text(curatedName ?? "Set curated course")
                        .font(AppFont.bodyLarge)
                        .italic()
                        .foregroundStyle(curatedName != nil ? palette.ink : palette.flag)
                    Spacer()
                    Text("›")
                        .font(AppFont.metadata)
                        .foregroundStyle(palette.ink2)
                }
            }
            .buttonStyle(.plain)
            if curatedName == nil {
                Text("Link this round to a curated course to enable green-anchor capture and distance-to-green.")
                    .font(AppFont.micro)
                    .tracking(0.8)
                    .foregroundStyle(palette.ink3)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var resumeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                onResume?()
            } label: {
                HStack {
                    Text("Resume")
                        .font(AppFont.cta)
                        .italic()
                        .fontWeight(.regular)
                        .foregroundStyle(palette.paper.opacity(0.85))
                    Text("round")
                        .font(AppFont.cta)
                        .foregroundStyle(palette.paper)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(palette.flag)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: Color.black.opacity(0.25), radius: 0, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            Text("If you ended the round by mistake, tap to reopen it. Tracking will resume on the last hole.")
                .font(AppFont.micro)
                .tracking(0.8)
                .foregroundStyle(palette.ink3)
        }
    }

    private var deleteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DANGER ZONE")
                    .font(AppFont.stamp)
                    .tracking(1.4)
                    .foregroundStyle(palette.red)
                Spacer()
                Rectangle().fill(palette.red.opacity(0.25)).frame(height: 1)
            }
            Button {
                showDeleteConfirm = true
            } label: {
                HStack {
                    Text("Delete round")
                        .font(AppFont.bodyLarge)
                        .italic()
                        .foregroundStyle(palette.red)
                    Spacer()
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.red)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(palette.red, lineWidth: 1.2)
                )
            }
            .buttonStyle(.plain)
            Text("Permanently removes this round and every hole, shot, and penalty inside it. There's no undo.")
                .font(AppFont.micro)
                .tracking(0.8)
                .foregroundStyle(palette.ink3)
        }
    }

    private func performDelete() {
        do {
            try RoundRepository.delete(round)
            onDeleted?()
            dismiss()
        } catch {
            loadError = "Delete failed: \(error.localizedDescription)"
        }
    }


    // MARK: - Score helpers

    private func holeScore(_ hole: Hole) -> Int {
        let s = shotsByHole[hole.id]?.count ?? 0
        let p = (penaltiesByHole[hole.id] ?? []).reduce(0) { $0 + $1.strokeCount }
        return s + p
    }

    private var totalShots: Int {
        shotsByHole.values.reduce(0) { $0 + $1.count }
    }

    private var totalPenaltyStrokes: Int {
        penaltiesByHole.values.reduce(0) { acc, list in
            acc + list.reduce(0) { $0 + $1.strokeCount }
        }
    }

    private var totalScore: Int { totalShots + totalPenaltyStrokes }

    private var totalPar: Int {
        holes.reduce(0) { $0 + ($1.par ?? 0) }
    }

    private var scoreVsPar: String? {
        let pars = holes.compactMap { $0.par }
        guard !pars.isEmpty else { return nil }
        return deltaString(totalScore - totalPar)
    }

    private func deltaString(_ d: Int) -> String {
        if d > 0 { return "+\(d)" }
        if d == 0 { return "E" }
        return "\(d)"
    }

    // MARK: - Data loading

    private func reload() {
        do {
            let allHoles = try HoleRepository.holesForRound(round.id)
            holes = trimTrailingEmptyHole(allHoles).sorted { $0.holeNumber < $1.holeNumber }

            var shotsMap: [UUID: [Shot]] = [:]
            var penaltiesMap: [UUID: [Penalty]] = [:]
            for hole in holes {
                shotsMap[hole.id] = try ShotRepository.shotsForHole(hole.id)
                penaltiesMap[hole.id] = try PenaltyRepository.penaltiesForHole(hole.id)
            }
            shotsByHole = shotsMap
            penaltiesByHole = penaltiesMap

            // Curated catalog + the round's linked course name (if any).
            curatedCourses = (try? CourseDataRepository.allCourses()) ?? []
            if let cid = round.curatedCourseId {
                curatedName = curatedCourses.first { $0.id == cid }?.name
            } else {
                curatedName = nil
            }

            // Ordinal (chronological) for "Official Card · No.": position among
            // all rounds, oldest = 1.
            let all = try RoundRepository.allRounds()
            let oldestFirst = all.sorted { $0.startedAt < $1.startedAt }
            roundOrdinal = (oldestFirst.firstIndex(where: { $0.id == round.id }) ?? -1) + 1

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

    private func setCurated(_ id: String?) {
        do {
            try RoundRepository.setCuratedCourseId(roundID: round.id, id: id)
            round.curatedCourseId = id
            // Adopt the curated course's name as the label too (same as the
            // in-round link) — replaces a wrong auto-detected POI name like
            // "Fountains" with the real "The Oaks at the Welk".
            if let id, let name = curatedCourses.first(where: { $0.id == id })?.name {
                round.courseName = name
                try RoundRepository.update(round)
            }
            showCoursePicker = false
            reload()
        } catch {
            loadError = "Couldn't set course: \(error.localizedDescription)"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
