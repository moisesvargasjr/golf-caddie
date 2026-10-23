import SwiftUI

/// The printed-card scorecard for the expanded (unfolded) screen: cream card,
/// double-rule border, all 18 holes in one row, handwritten scores. The
/// folded screen keeps `InRoundScorecardSheet`'s compact card.
struct PhysicalScorecardView: View {
    let round: Round
    /// Live hole (tinted, left blank); nil for a finished round.
    let currentHoleNumber: Int?
    let bag: [Club]
    let curatedCourseId: String?
    let onDismiss: () -> Void

    @Environment(\.palette) private var appPalette
    @State private var model = ScorecardModel(columns: [], hasStrokeIndex: false)
    @State private var holes: [Hole] = []
    @State private var courseName: String?
    @State private var selectedHole: Int?
    @State private var loadError: String?
    /// Render a supplied model without touching the database (snapshot tests).
    private var isPreview = false

    init(round: Round, currentHoleNumber: Int?, bag: [Club], curatedCourseId: String?,
         onDismiss: @escaping () -> Void) {
        self.round = round
        self.currentHoleNumber = currentHoleNumber
        self.bag = bag
        self.curatedCourseId = curatedCourseId
        self.onDismiss = onDismiss
    }

    /// Card only, from a prepared model — for `ImageRenderer` snapshots.
    static func previewCard(round: Round, model: ScorecardModel, courseName: String,
                            currentHoleNumber: Int?) -> some View {
        var view = PhysicalScorecardView(round: round, currentHoleNumber: currentHoleNumber,
                                         bag: [], curatedCourseId: nil, onDismiss: {})
        view._model = State(initialValue: model)
        view._courseName = State(initialValue: courseName)
        view.isPreview = true
        return view.card
    }

    /// Card width at which all 22 columns read comfortably.
    static let minCardWidth: CGFloat = 820

    private var ink: Color { CardInk.palette.ink }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                // The safe-area-respecting column: "‹ DONE" stays put; the card
                // scrolls (>= 820 pt wide) inside the safe area, never under
                // the trailing status strip.
                VStack(alignment: .leading, spacing: 4) {
                    closeRow
                        .padding(.horizontal, 16)
                    GeometryReader { proxy in
                        ScrollView([.horizontal, .vertical]) {
                            VStack(alignment: .leading, spacing: 10) {
                                card
                                    .frame(width: max(Self.minCardWidth, proxy.size.width - 32))
                                if let loadError {
                                    Text(loadError).font(AppFont.micro).foregroundStyle(appPalette.red)
                                }
                            }
                            .padding(16)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { if !isPreview { reload() } }
        }
    }

    private var closeRow: some View {
        Button(action: onDismiss) {
            Text("‹ DONE")
                .font(AppFont.stampMd).tracking(1.4)
                .foregroundStyle(appPalette.ink)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !model.columns.isEmpty {
                PhysicalScorecardGrid(model: model, highlightedHole: currentHoleNumber,
                                      selectedHole: $selectedHole)
                footer
            }
        }
        .padding(14)
        .background(CardInk.innerCard)
        .overlay(Rectangle().stroke(ink.opacity(0.5), lineWidth: 1))
        .padding(12)
        .background(CardInk.palette.paper)
        .overlay(Rectangle().stroke(ink, lineWidth: 2))
        .overlay(Rectangle().stroke(ink, lineWidth: 1).padding(4))
        .environment(\.palette, CardInk.palette)
        // Hard offset shadow drawn as a shape — `.shadow` here would ghost every glyph.
        .background(Rectangle().fill(Color.black.opacity(0.25)).offset(x: 4, y: 4))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().stroke(ink, lineWidth: 1.5).frame(width: 52, height: 52)
                Circle().stroke(ink, lineWidth: 0.8).frame(width: 44, height: 44)
                Image(systemName: "flag.fill").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CardInk.palette.flag)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(courseName ?? round.courseName ?? "Golf course")
                    .font(.custom(AppFont.serifName, size: 30).italic().weight(.bold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("SCORECARD")
                    .font(AppFont.metadata).tracking(1.6)
                    .foregroundStyle(CardInk.palette.ink2)
            }
            Spacer(minLength: 12)
            handField("DATE", round.startedAt.formatted(.dateTime.month(.abbreviated).day().year()))
            handField("PLAYER", "")
        }
    }

    private func handField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.isEmpty ? " " : value)
                .font(CardInk.hand(18))
                .foregroundStyle(CardInk.graphite)
            Rectangle().fill(ink).frame(height: 1)
            Text(label).font(AppFont.micro).tracking(1.4).foregroundStyle(CardInk.palette.ink3)
        }
        .frame(width: 140, alignment: .leading)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(alignment: .top, spacing: 12) {
            selectedPanel
            statBox("GROSS", model.total.score.map(String.init) ?? "—",
                    sub: model.grossToPar.map { $0 == 0 ? "E" : ($0 > 0 ? "+\($0)" : "\($0)") })
            statBox("PUTTS", model.total.putts.map(String.init) ?? "—", sub: nil)
            statBox("GIR", "\(model.girCount)", sub: "OF 18")
            legend
        }
    }

    private var selectedColumn: ScorecardColumn? {
        let n = selectedHole ?? currentHoleNumber ?? 1
        return model.columns.indices.contains(n - 1) ? model.columns[n - 1] : nil
    }

    private var selectedPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let col = selectedColumn {
                Text(panelTitle(col))
                    .font(AppFont.stamp).tracking(1.4).foregroundStyle(ink)
                Text(col.story ?? "Not played yet")
                    .font(CardInk.hand(17)).foregroundStyle(CardInk.graphite)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if col.isConfirmed, let index = confirmedHoles.firstIndex(where: { $0.holeNumber == col.number }) {
                    NavigationLink {
                        HoleDetailView(holes: confirmedHoles, bag: bag, curatedCourseId: curatedCourseId,
                                       startIndex: index, onChanged: { reload() })
                    } label: {
                        Text("OPEN HOLE ›")
                            .font(AppFont.stamp).tracking(1.4)
                            .foregroundStyle(CardInk.palette.flag)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .overlay(Rectangle().stroke(ink.opacity(0.5), lineWidth: 1))
    }

    private func panelTitle(_ col: ScorecardColumn) -> String {
        var parts = ["HOLE \(col.number)", col.par.map { "PAR \($0)" } ?? "PAR —"]
        if let y = col.yards { parts.append("\(y) YD") }
        return parts.joined(separator: " · ")
    }

    private func statBox(_ title: String, _ value: String, sub: String?) -> some View {
        VStack(spacing: 2) {
            Text(title).font(AppFont.micro).tracking(1.4).foregroundStyle(CardInk.palette.ink2)
            Text(value).font(CardInk.hand(30)).foregroundStyle(CardInk.graphite)
            Text(sub ?? " ").font(AppFont.stamp).tracking(1.2).foregroundStyle(ink)
        }
        .frame(width: 84, height: 96)
        .overlay(Rectangle().stroke(ink.opacity(0.5), lineWidth: 1))
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                legendItem(.circle, "BIRDIE")
                legendItem(.doubleCircle, "EAGLE")
            }
            HStack(spacing: 10) {
                legendItem(.square, "BOGEY")
                legendItem(.doubleSquare, "DBL+")
            }
            signature("SCORER", "Golf Caddie")
            signature("ATTEST", "")
        }
        .frame(width: 190, alignment: .leading)
    }

    private func legendItem(_ mark: ScoreMark, _ text: String) -> some View {
        HStack(spacing: 4) {
            ScoreMarkView(score: 4, mark: mark).scaleEffect(0.6).frame(width: 22, height: 22)
            Text(text).font(AppFont.micro).tracking(1).foregroundStyle(CardInk.palette.ink2)
        }
    }

    private func signature(_ label: String, _ value: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(label).font(AppFont.micro).tracking(1.2).foregroundStyle(CardInk.palette.ink3)
            VStack(spacing: 0) {
                Text(value.isEmpty ? " " : value).font(CardInk.hand(15)).foregroundStyle(CardInk.graphite)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(ink).frame(height: 1)
            }
        }
    }

    // MARK: Data

    private var confirmedHoles: [Hole] { holes.filter { $0.confirmedAt != nil } }

    private func reload() {
        do {
            holes = try HoleRepository.holesForRound(round.id)
            let inputs = holes.map { hole in
                ScorecardModel.HoleInput(
                    hole: hole,
                    shots: (try? ShotRepository.shotsForHole(hole.id)) ?? [],
                    penaltyStrokes: ((try? PenaltyRepository.penaltiesForHole(hole.id)) ?? [])
                        .reduce(0) { $0 + $1.strokeCount })
            }
            let course = curatedCourseId.flatMap { try? CourseDataRepository.course(byId: $0) }
            let anchors = curatedCourseId.flatMap { try? LocalAnchorRepository.anchorsForCourse($0) } ?? []
            courseName = course?.name
            model = ScorecardModel.build(
                holes: inputs, course: course,
                localAnchors: Dictionary(anchors.map { ($0.holeNumber, $0) }, uniquingKeysWith: { a, _ in a }))
            loadError = nil
        } catch {
            loadError = "Couldn't load the card: \(error.localizedDescription)"
        }
    }
}
