import SwiftUI

/// The traditional double-ruled card for the fully open Duo held wide, for the
/// live round and finished rounds (Scorecard-Open / Round-Open mockups): all
/// 18 holes in one row, handwritten scores, the picked hole's story and its
/// one action, GROSS / PUTTS / GIR, legend and signature lines.
struct PhysicalScorecardView: View {
    let content: ScorecardContent
    @Binding var selectedHole: Int?

    /// Card only, from a prepared model — for `ImageRenderer` snapshots.
    static func previewCard(round: Round, model: ScorecardModel, courseName: String,
                            currentHoleNumber: Int?) -> some View {
        let content = ScorecardContent(
            round: round, model: model, courseName: courseName, currentHole: currentHoleNumber,
            variant: .traditional, canOpenHole: true, onDismiss: {}, onOpenCourseMap: nil, onPick: { _ in })
        return PhysicalScorecardView(content: content, selectedHole: .constant(currentHoleNumber))
            .card(stretch: false)
    }

    private let ink = CardInk.ink

    /// The hole the panel describes: the pick, else the live hole, else 1.
    private var shownHole: Int { selectedHole ?? content.currentHole ?? 1 }

    var body: some View {
        // Fill the screen when the card fits; scroll when it can't (large text).
        ViewThatFits(in: .vertical) {
            card(stretch: true)
            ScrollView(.vertical) { card(stretch: false) }
                .scrollIndicators(.hidden)
        }
        .padding(16)
    }

    private func card(stretch: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            PhysicalScorecardGrid(model: content.model, currentHole: content.currentHole,
                                  selectedHole: shownHole, onSelect: { selectedHole = $0 })
            footer
                .frame(minHeight: 120, maxHeight: stretch ? .infinity : nil, alignment: .top)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 15)
        .frame(maxHeight: stretch ? .infinity : nil, alignment: .top)
        .background(CardInk.innerCard, ignoresSafeAreaEdges: [])
        // CSS `3px double`: two 1 pt rules with a 1 pt gap.
        .overlay(Rectangle().strokeBorder(ink, lineWidth: 1))
        .overlay(Rectangle().strokeBorder(ink, lineWidth: 1).padding(2))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            ScorecardOutlinedButton(title: content.dismissTitle, action: content.onDismiss)
                .accessibilityIdentifier("scorecard.dismiss")
            ScorecardFlagBadge()
            VStack(alignment: .leading, spacing: 0) {
                Text(content.courseName)
                    .font(.custom(AppFont.serifName, size: 28).italic().weight(.bold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("OFFICIAL SCORECARD · \(content.status)")
                    .font(CardInk.mono(10)).tracking(1.2)
                    .foregroundStyle(CardInk.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            handField("DATE", content.round.startedAt.formatted(
                .dateTime.month(.twoDigits).day(.twoDigits).year(.twoDigits)), minWidth: 84)
            handField("PLAYER", PlayerProfile.name, minWidth: 100)
            if let openMap = content.onOpenCourseMap {
                ScorecardCourseMapButton(action: openMap)
            }
            if let menu = content.roundMenu {
                menu
            }
        }
    }

    private func handField(_ label: String, _ value: String, minWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(CardInk.mono(10)).foregroundStyle(CardInk.ink2)
            Text(value.isEmpty ? " " : value)
                .font(CardInk.hand(22))
                .foregroundStyle(CardInk.graphite)
                .lineLimit(1)
                .frame(minWidth: minWidth, alignment: .leading)
                .overlay(alignment: .bottom) { Rectangle().fill(ink).frame(height: 1) }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(alignment: .top, spacing: 12) {
            selectedPanel
            // GROSS · PUTTS over GIR · FIR (Round-Open-History).
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    ScorecardStatBox(title: "GROSS", value: ScorecardText.number(content.model.total.score),
                                     sub: content.model.grossToPar.map { ScorecardText.toPar($0) },
                                     subColor: CardInk.palette.red, valueSize: 30, alignment: .center)
                        .accessibilityIdentifier("scorecard.stat.gross")
                    ScorecardStatBox(title: "PUTTS", value: ScorecardText.number(content.model.total.putts),
                                     valueSize: 30, alignment: .center)
                }
                GridRow {
                    ScorecardStatBox(title: "GIR", value: "\(content.model.girCount)",
                                     sub: "OF \(content.model.playedCount)",
                                     valueSize: 30, alignment: .center)
                    ScorecardStatBox(title: "FIR", value: content.model.firHits.map(String.init) ?? "—",
                                     sub: content.model.firAnswered.map { "OF \($0)" },
                                     valueSize: 30, alignment: .center)
                }
            }
            .frame(width: 196)
            .frame(minHeight: 110, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                legend
                if !content.history.isEmpty { CourseHistoryTable(rows: content.history, onOpen: content.onOpenRound) }
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 10) {
                    signature("SCORER", "Golf Caddie")
                    signature("ATTEST", "")
                }
            }
            .frame(width: 300)
            .frame(minHeight: 110, maxHeight: .infinity)
        }
    }

    private var selectedPanel: some View {
        let column = content.column(shownHole)
        let pick = content.pick(shownHole)
        return VStack(alignment: .leading, spacing: 4) {
            Text(panelTitle(column))
                .font(CardInk.mono(10)).tracking(0.8)
                .foregroundStyle(CardInk.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(ScorecardText.story(column, currentHole: content.currentHole,
                                     startingHole: content.round.startingHole))
                .font(CardInk.hand(24))
                .foregroundStyle(CardInk.graphite)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 4)
            ScorecardPickButtons(content: content, pick: pick, expands: true)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 110, maxHeight: .infinity, alignment: .topLeading)
        .background(CardInk.palette.paper, ignoresSafeAreaEdges: [])
        .overlay(Rectangle().strokeBorder(ink, lineWidth: 1.5))
    }

    private func panelTitle(_ column: ScorecardColumn) -> String {
        var parts = ["HOLE \(column.number)"]
        if let par = column.par { parts.append("PAR \(par)") }
        if let yards = column.yards { parts.append("\(yards) YD") }
        parts.append("TAP ANY HOLE NUMBER")
        return parts.joined(separator: " · ")
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().stroke(ink, lineWidth: 1.5).frame(width: 18, height: 18)
                legendText("BIRDIE")
                Rectangle().stroke(ink, lineWidth: 1.5).frame(width: 16, height: 16)
                legendText("BOGEY")
                ZStack {
                    Rectangle().stroke(ink, lineWidth: 1.5).frame(width: 18, height: 18)
                    Rectangle().stroke(ink, lineWidth: 1.5).frame(width: 12, height: 12)
                }
                legendText("DBL+")
                Text("●").font(.system(size: 10)).foregroundStyle(ink)
                legendText("HIT")
            }
            if let note = content.model.notPlayedNote {
                HStack(spacing: 8) {
                    NotPlayedMark().frame(width: 26, height: 20)
                    legendText("NOT PLAYED")
                }
                legendText(note)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Circle, birdie. Square, bogey. Double square, double bogey or worse. Dot, hit."
                            + (content.model.notPlayedNote.map { " NP, not played. \($0.lowercased())." } ?? ""))
    }

    private func legendText(_ text: String) -> some View {
        Text(text).font(CardInk.mono(9)).foregroundStyle(CardInk.ink2)
    }

    private func signature(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            legendText(label)
            Text(value.isEmpty ? " " : value)
                .font(CardInk.hand(20))
                .foregroundStyle(CardInk.graphite)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) { Rectangle().fill(ink).frame(height: 1) }
        }
    }
}

/// AT THIS COURSE: your best earlier rounds here; each row opens its card.
struct CourseHistoryTable: View {
    let rows: [CourseHistoryRow]
    let onOpen: ((Round) -> Void)?
    private let ink = CardInk.ink

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("AT THIS COURSE").tracking(1)
                Spacer()
                Text("YOUR BEST \(rows.count)").font(CardInk.mono(8))
            }
            .font(CardInk.mono(9))
            .foregroundStyle(CardInk.palette.paper)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ink, ignoresSafeAreaEdges: [])
            .accessibilityAddTraits(.isHeader)
            ForEach(rows) { row in
                Button { onOpen?(row.round) } label: { label(row) }
                    .buttonStyle(.plain)
                    .disabled(onOpen == nil)
                    .accessibilityLabel(row.accessibilityLabel)
                    .accessibilityIdentifier("scorecard.history.row")
            }
        }
        .background(CardInk.palette.paper, ignoresSafeAreaEdges: [])
        .overlay(Rectangle().strokeBorder(ink, lineWidth: 1.5))
    }

    private func label(_ row: CourseHistoryRow) -> some View {
        HStack(spacing: 8) {
            Text(row.dateText).font(CardInk.mono(10)).foregroundStyle(CardInk.ink2).frame(width: 48, alignment: .leading)
            Text(row.note).font(CardInk.mono(8)).tracking(0.6)
                .foregroundStyle(row.isComplete ? CardInk.ink2 : CardInk.palette.red)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(row.score)").font(CardInk.serif(18)).foregroundStyle(ink)
            Text(row.toParText ?? "").font(CardInk.mono(10)).foregroundStyle(ink).frame(width: 30, alignment: .trailing)
            if onOpen != nil {
                Text("›").font(CardInk.serif(16)).foregroundStyle(ink)
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 44)
        .background(row.isComplete ? Color.clear : ink.opacity(0.05), ignoresSafeAreaEdges: [])
        .overlay(alignment: .top) { Rectangle().fill(ink.opacity(0.2)).frame(height: 1) }
        .contentShape(Rectangle())
    }
}
