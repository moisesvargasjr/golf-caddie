import SwiftUI

/// Home / landing screen — "The Fairway Logbook" masthead.
///
/// Shown when no round is active. Hosts the last-completed-round summary
/// (tap → push Summary), the Begin-new-round CTA, and navigation to the
/// Logbook (rounds list) and Settings.
struct HomeView: View {
    @Binding var bag: [Club]
    let onStartRound: (Int) -> Void
    @State private var startingHole = 1
    let actionError: String?

    @Environment(\.palette) private var palette
    @AppStorage("units") private var unitsRaw: String = Units.yards.rawValue
    @AppStorage("glassesServerEnabled") private var glassesEnabled = false

    @State private var lastSummary: LastRoundSummary?
    @State private var roundCount: Int = 0
    @State private var loadError: String?
    @State private var showBagEditor: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            PaperBackground()

            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.horizontal, 28)
                    .padding(.top, 6)

                masthead
                    .padding(.horizontal, 28)
                    .padding(.top, 18)

                dateStrip
                    .padding(.horizontal, 28)
                    .padding(.top, 10)

                SingleRule(weight: .thin, opacity: 0.85)
                    .padding(.horizontal, 28)
                    .padding(.top, 24)

                if let summary = lastSummary {
                    lastEntryBlock(summary: summary)
                        .padding(.horizontal, 28)
                        .padding(.top, 22)
                } else {
                    emptyLastEntry
                        .padding(.horizontal, 28)
                        .padding(.top, 22)
                }

                Spacer(minLength: 12)

                footer
                    .padding(.horizontal, 28)
                    .padding(.bottom, 36)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showBagEditor) {
            BagSetupView(
                initialBag: bag,
                onCancel: { showBagEditor = false }
            ) { saved in
                bag = saved
                showBagEditor = false
            }
        }
        .onAppear { refresh() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center) {
            Stamp(text: "Caddie · No. \(roundCount)")

            Spacer()

            // G2 linked indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(glassesEnabled ? palette.red : palette.ink3)
                    .frame(width: 6, height: 6)
                Text(glassesEnabled ? "G2 LINKED" : "G2 OFF")
                    .font(AppFont.metadata)
                    .tracking(1.2)
                    .foregroundStyle(glassesEnabled ? palette.ink2 : palette.ink3)
            }

            // Settings gear
            NavigationLink {
                SettingsView(bag: $bag)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.ink2)
            }
            .padding(.leading, 10)
        }
    }

    // MARK: - Masthead

    private var masthead: some View {
        ItalicHeadline(
            lines: ["The", "Fairway", "Logbook."],
            font: AppFont.masthead,
            color: palette.ink,
            tracking: -2,
            lineSpacing: -6
        )
    }

    private var dateStrip: some View {
        Text(Self.dateString(Date()))
            .font(AppFont.metadata)
            .tracking(1)
            .foregroundStyle(palette.ink2)
    }

    // MARK: - Last entry block

    private func lastEntryBlock(summary: LastRoundSummary) -> some View {
        NavigationLink {
            RoundReviewView(
                round: summary.round,
                bag: bag,
                onResume: nil,
                onDismiss: nil,
                onDeleted: { refresh() }
            )
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text("LAST ENTRY · TAP TO REVIEW")
                    .font(AppFont.stamp)
                    .tracking(1.4)
                    .foregroundStyle(palette.ink3)

                Text(summary.courseTitle)
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(palette.ink)
                    .padding(.top, 4)

                HStack(alignment: .bottom, spacing: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SCORE")
                            .font(AppFont.stamp)
                            .tracking(1)
                            .foregroundStyle(palette.ink3)
                        Text("\(summary.score)")
                            .font(AppFont.distanceHero)
                            .tracking(-2.5)
                            .foregroundStyle(palette.ink)
                            .tabularNumerals()
                            .padding(.top, -4)
                    }

                    if summary.delta != 0 {
                        Stamp(
                            text: summary.deltaString,
                            color: summary.delta > 0 ? palette.red : palette.ink
                        )
                        .padding(.bottom, 8)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("DURATION")
                            .font(AppFont.stamp)
                            .tracking(1)
                            .foregroundStyle(palette.ink3)
                        Text(summary.durationString)
                            .font(.custom(AppFont.monoName, size: 17).weight(.bold))
                            .foregroundStyle(palette.ink)
                            .tabularNumerals()
                    }
                    .padding(.bottom, 6)
                }
                .padding(.top, 14)

                miniScorecard(holes: summary.holeScores)
                    .padding(.top, 18)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyLastEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NO ROUNDS YET")
                .font(AppFont.stamp)
                .tracking(1.4)
                .foregroundStyle(palette.ink3)
            Text("Begin your first round below.")
                .font(AppFont.bodyLarge)
                .italic()
                .foregroundStyle(palette.ink2)
        }
    }

    private func miniScorecard(holes: [(num: Int, score: Int)]) -> some View {
        // Show up to 9 cells (front nine ribbon, matching prototype).
        let cells = Array(holes.prefix(9))
        return HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { idx, cell in
                VStack(spacing: 2) {
                    Text("\(cell.num)")
                        .font(.custom(AppFont.monoName, size: 9).weight(.bold))
                        .foregroundStyle(palette.ink3)
                    Text("\(cell.score)")
                        .font(.custom(AppFont.monoName, size: 14).weight(.bold))
                        .foregroundStyle(palette.ink)
                        .tabularNumerals()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .overlay(alignment: .trailing) {
                    if idx < cells.count - 1 {
                        Rectangle().fill(palette.rule).frame(width: 1)
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(palette.rule).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.rule).frame(height: 1)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    showBagEditor = true
                } label: {
                    Stamp(text: "The Bag · \(bag.count) clubs")
                }
                .buttonStyle(.plain)
                Spacer()
                NavigationLink {
                    RoundListView(bag: bag)
                } label: {
                    Text("LOGBOOK ›")
                        .font(AppFont.metadata)
                        .tracking(1.2)
                        .foregroundStyle(palette.ink)
                }
            }

            if let actionError {
                Text(actionError)
                    .font(AppFont.micro)
                    .tracking(1.2)
                    .foregroundStyle(palette.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            startHoleStepper
            beginCTA
        }
    }

    /// Pick the starting hole (default 1). Ignore it for a normal front-nine
    /// start; bump to 10 to begin on the back nine.
    private var startHoleStepper: some View {
        HStack {
            Text("START ON HOLE")
                .font(AppFont.stamp).tracking(1.4)
                .foregroundStyle(palette.ink3)
            Spacer()
            HStack(spacing: 16) {
                stepButton("‹") { if startingHole > 1 { startingHole -= 1 } }
                Text("\(startingHole)")
                    .font(.custom(AppFont.serifName, size: 22).italic().weight(.bold))
                    .foregroundStyle(palette.ink)
                    .frame(minWidth: 26)
                stepButton("›") { if startingHole < 18 { startingHole += 1 } }
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    private func stepButton(_ glyph: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.custom(AppFont.serifName, size: 26).weight(.bold))
                .foregroundStyle(palette.ink)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
    }

    private var beginCTA: some View {
        Button(action: { onStartRound(startingHole) }) {
            HStack(spacing: 6) {
                Text("Begin")
                    .font(AppFont.cta)
                    .italic()
                    .fontWeight(.regular)
                    .foregroundStyle(palette.paper.opacity(0.85))
                Text("new round")
                    .font(AppFont.cta)
                    .foregroundStyle(palette.paper)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(palette.ink)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: Color.black.opacity(0.25), radius: 0, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data loading

    private func refresh() {
        do {
            let rounds = try RoundRepository.allRounds()
            roundCount = rounds.count
            // First completed round = most recent ended (allRounds returns desc by startedAt).
            if let lastEnded = rounds.first(where: { $0.endedAt != nil }) {
                lastSummary = try Self.buildSummary(for: lastEnded)
            } else {
                lastSummary = nil
            }
        } catch {
            loadError = "Couldn't load rounds: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE · MMM d · yyyy"
        return formatter.string(from: date).uppercased()
    }

    private static func buildSummary(for round: Round) throws -> LastRoundSummary {
        let holes = try HoleRepository.holesForRound(round.id)
            .sorted { $0.holeNumber < $1.holeNumber }
        var totalShots = 0
        var totalPar = 0
        var holeScores: [(num: Int, score: Int)] = []
        for hole in holes {
            let shots = (try? ShotRepository.shotsForHole(hole.id).count) ?? 0
            let penaltyStrokes = ((try? PenaltyRepository.penaltiesForHole(hole.id)) ?? [])
                .reduce(0) { $0 + $1.strokeCount }
            let holeTotal = shots + penaltyStrokes
            totalShots += holeTotal
            if let par = hole.par {
                totalPar += par
            }
            if hole.confirmedAt != nil, holeTotal > 0 {
                holeScores.append((num: hole.holeNumber, score: holeTotal))
            }
        }
        let delta = totalShots - totalPar
        let duration: TimeInterval = {
            guard let end = round.endedAt else { return 0 }
            return end.timeIntervalSince(round.startedAt)
        }()
        return LastRoundSummary(
            round: round,
            courseTitle: round.courseName ?? "Untitled round",
            score: totalShots,
            par: totalPar,
            delta: delta,
            durationString: formatDuration(duration),
            holeScores: holeScores
        )
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "—" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

private struct LastRoundSummary: Equatable {
    let round: Round
    let courseTitle: String
    let score: Int
    let par: Int
    let delta: Int
    let durationString: String
    let holeScores: [(num: Int, score: Int)]

    var deltaString: String {
        delta > 0 ? "+\(delta)" : "\(delta)"
    }

    static func == (lhs: LastRoundSummary, rhs: LastRoundSummary) -> Bool {
        lhs.round == rhs.round
            && lhs.score == rhs.score
            && lhs.par == rhs.par
            && lhs.holeScores.map(\.num) == rhs.holeScores.map(\.num)
            && lhs.holeScores.map(\.score) == rhs.holeScores.map(\.score)
    }
}

#Preview {
    NavigationStack {
        HomeView(
            bag: .constant(ClubConfiguration.recommendedDefault.bag.compactMap { id in
                Club.seedCatalog.first { $0.id == id }
            }),
            onStartRound: { _ in },
            actionError: nil
        )
    }
    .themedRoot()
}
