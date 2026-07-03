import SwiftUI

/// "The Logbook." — list of past rounds. Each row shows date column + course
/// name + score/delta. Tap a row to push the Summary for that round.
struct RoundListView: View {
    let bag: [Club]

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var rounds: [RoundRowData] = []
    @State private var loadError: String?
    @State private var roundPendingDelete: RoundRowData?

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
                        .padding(.top, 18)

                    columnHeader
                        .padding(.horizontal, 24)
                        .padding(.top, 28)

                    if rounds.isEmpty {
                        emptyState
                            .padding(.horizontal, 24)
                            .padding(.top, 40)
                    } else {
                        ForEach(rounds) { row in
                            NavigationLink {
                                RoundReviewView(
                                    round: row.round,
                                    bag: bag,
                                    onDeleted: { reload() }
                                )
                            } label: {
                                roundRow(row)
                                    .padding(.horizontal, 24)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    roundPendingDelete = row
                                } label: {
                                    Label("Delete round", systemImage: "trash")
                                }
                            }
                        }
                    }

                    if let loadError {
                        Text(loadError)
                            .font(AppFont.micro)
                            .tracking(1.2)
                            .foregroundStyle(palette.red)
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                    }

                    Spacer(minLength: 40)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert(
            "Delete this round?",
            isPresented: Binding(
                get: { roundPendingDelete != nil },
                set: { if !$0 { roundPendingDelete = nil } }
            ),
            presenting: roundPendingDelete
        ) { row in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                delete(row)
            }
        } message: { row in
            let course = row.courseTitle.isEmpty ? "this round" : row.courseTitle
            Text("\(course) and all its holes, shots, and penalties will be permanently deleted.")
        }
        .onAppear { reload() }
    }

    // MARK: - Nav row

    private var navRow: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text("‹ HOME")
                    .font(AppFont.metadata)
                    .tracking(1.4)
                    .foregroundStyle(palette.ink)
            }

            Spacer()

            Stamp(text: yearStamp)
        }
    }

    private var yearStamp: String {
        let year = Calendar.current.component(.year, from: Date())
        return "\(year)"
    }

    // MARK: - Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 6) {
            ItalicHeadline(
                lines: ["The", "Logbook."],
                font: AppFont.masthead,
                color: palette.ink,
                tracking: -2,
                lineSpacing: -6
            )

            Text(summaryCaption)
                .font(AppFont.metadata)
                .tracking(1.2)
                .foregroundStyle(palette.ink2)
                .padding(.top, 4)
        }
    }

    private var summaryCaption: String {
        if rounds.isEmpty { return "0 ENTRIES" }
        let endedRounds = rounds.filter { $0.score > 0 }
        let countLabel = "\(rounds.count) ENTRIES"
        guard !endedRounds.isEmpty else { return countLabel }
        let avg = Int((Double(endedRounds.map(\.score).reduce(0, +)) / Double(endedRounds.count)).rounded())
        let best = endedRounds.map(\.score).min() ?? 0
        return "\(countLabel) · AVG \(avg) · BEST \(best)"
    }

    // MARK: - Column header

    private var columnHeader: some View {
        HStack {
            Text("DATE ↓")
                .font(AppFont.micro)
                .tracking(1.4)
                .foregroundStyle(palette.ink2)
            Spacer()
            Text("COURSE")
                .font(AppFont.micro)
                .tracking(1.4)
                .foregroundStyle(palette.ink2)
            Spacer()
            Text("SCORE")
                .font(AppFont.micro)
                .tracking(1.4)
                .foregroundStyle(palette.ink2)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.ink).frame(height: 2)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.ink).frame(height: 1)
        }
    }

    // MARK: - Round row

    private func roundRow(_ row: RoundRowData) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Date column
            VStack(alignment: .leading, spacing: 2) {
                Text(row.month.uppercased())
                    .font(AppFont.micro)
                    .tracking(1.4)
                    .foregroundStyle(palette.ink2)
                Text("\(row.day)")
                    .font(.custom(AppFont.serifName, size: 26).weight(.bold))
                    .foregroundStyle(palette.ink)
                    .tabularNumerals()
            }
            .frame(width: 48, alignment: .leading)

            // Middle: course + duration
            VStack(alignment: .leading, spacing: 2) {
                Text(row.courseTitle)
                    .font(AppFont.bodyLarge)
                    .italic()
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                Text(row.captionLine.uppercased())
                    .font(AppFont.micro)
                    .tracking(1.2)
                    .foregroundStyle(palette.ink3)
            }

            Spacer()

            // Score + delta
            VStack(alignment: .trailing, spacing: 2) {
                if row.score > 0 {
                    Text("\(row.score)")
                        .font(.custom(AppFont.serifName, size: 28).weight(.bold))
                        .foregroundStyle(palette.ink)
                        .tabularNumerals()
                    if row.delta != 0 {
                        Text(row.deltaString)
                            .font(AppFont.metadata)
                            .tracking(1.2)
                            .foregroundStyle(row.delta > 0 ? palette.red : palette.ink2)
                            .tabularNumerals()
                    }
                } else {
                    Text("— —")
                        .font(AppFont.metadata)
                        .tracking(1.2)
                        .foregroundStyle(palette.ink3)
                }
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.rule).frame(height: 1)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NO ROUNDS YET")
                .font(AppFont.stamp)
                .tracking(1.4)
                .foregroundStyle(palette.ink3)
            Text("Rounds will appear here once you play.")
                .font(AppFont.bodyLarge)
                .italic()
                .foregroundStyle(palette.ink2)
        }
    }

    // MARK: - Data

    private func reload() {
        do {
            let all = try RoundRepository.allRounds()
            rounds = all.map { Self.buildRow(for: $0) }
            loadError = nil
        } catch {
            loadError = "Failed: \(error.localizedDescription)"
        }
    }

    private func delete(_ row: RoundRowData) {
        do {
            try RoundRepository.delete(row.round)
            roundPendingDelete = nil
            reload()
        } catch {
            loadError = "Delete failed: \(error.localizedDescription)"
            roundPendingDelete = nil
        }
    }

    private static func buildRow(for round: Round) -> RoundRowData {
        let startedAt = round.startedAt
        let cal = Calendar.current
        let day = cal.component(.day, from: startedAt)
        let month = monthAbbrev(for: startedAt)
        let courseTitle = round.courseName?.isEmpty == false
            ? round.courseName!
            : "Untitled round"

        // Score totals
        var totalShots = 0
        var totalPar = 0
        var confirmedHoleCount = 0
        if let holes = try? HoleRepository.holesForRound(round.id) {
            for hole in holes {
                let shotsCount = (try? ShotRepository.shotsForHole(hole.id).count) ?? 0
                let penalties = ((try? PenaltyRepository.penaltiesForHole(hole.id)) ?? [])
                    .reduce(0) { $0 + $1.strokeCount }
                let holeTotal = shotsCount + penalties
                totalShots += holeTotal
                if let par = hole.par {
                    totalPar += par
                }
                if hole.confirmedAt != nil { confirmedHoleCount += 1 }
            }
        }

        let inProgress = round.endedAt == nil
        let durationLabel: String
        if inProgress {
            durationLabel = "In progress"
        } else if let endedAt = round.endedAt {
            durationLabel = formatDuration(endedAt.timeIntervalSince(round.startedAt))
        } else {
            durationLabel = "—"
        }

        let captionLine: String
        if inProgress {
            captionLine = "\(durationLabel) · hole \(confirmedHoleCount + 1)"
        } else if confirmedHoleCount > 0 {
            captionLine = "\(durationLabel) · \(confirmedHoleCount) holes"
        } else {
            captionLine = "\(durationLabel) · practice"
        }

        return RoundRowData(
            round: round,
            day: day,
            month: month,
            courseTitle: courseTitle,
            captionLine: captionLine,
            score: totalShots,
            delta: totalShots - totalPar
        )
    }

    private static func monthAbbrev(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f.string(from: date)
    }

    private static func formatDuration(_ s: TimeInterval) -> String {
        let total = Int(s.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - Row data

private struct RoundRowData: Identifiable {
    let round: Round
    let day: Int
    let month: String
    let courseTitle: String
    let captionLine: String
    let score: Int
    let delta: Int

    var id: UUID { round.id }

    var deltaString: String {
        delta > 0 ? "+\(delta)" : "\(delta)"
    }
}

#Preview {
    NavigationStack {
        RoundListView(bag: ClubConfiguration.recommendedDefault.bag.compactMap { id in
            Club.seedCatalog.first { $0.id == id }
        })
    }
    .themedRoot()
}
