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
        .background(CardInk.innerCard)
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
            handField("PLAYER", "", minWidth: 100)
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
            HStack(spacing: 6) {
                ScorecardStatBox(title: "GROSS", value: ScorecardText.number(content.model.total.score),
                                 sub: content.model.grossToPar.map { ScorecardText.toPar($0) },
                                 subColor: CardInk.palette.red, valueSize: 34, alignment: .center)
                    .accessibilityIdentifier("scorecard.stat.gross")
                ScorecardStatBox(title: "PUTTS", value: ScorecardText.number(content.model.total.putts),
                                 valueSize: 34, alignment: .center)
                ScorecardStatBox(title: "GIR", value: "\(content.model.girCount)", sub: "OF 18",
                                 valueSize: 34, alignment: .center)
            }
            .frame(width: 250)
            .frame(minHeight: 110, maxHeight: .infinity)
            legend
                .frame(width: 200)
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
            if let title = content.ctaTitle(pick) {
                ScorecardFilledButton(title: title, expands: true) { content.onPick(pick) }
                    .accessibilityIdentifier("scorecard.cta")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 110, maxHeight: .infinity, alignment: .topLeading)
        .background(CardInk.palette.paper)
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
            }
            Spacer(minLength: 4)
            signature("SCORER", "Golf Caddie")
            signature("ATTEST", "")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Circle, birdie. Square, bogey. Double square, double bogey or worse.")
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
