import SwiftUI
import UIKit

/// Share-sheet bridge (UIActivityViewController): the anchor / spike exports
/// (DEBUG) and a finished round's Share round.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    init(items: [Any]) {
        self.items = items
    }

    init(url: URL) {
        self.init(items: [url])
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// What a share sheet is about to share, so it can drive `.sheet(item:)`.
struct ShareItems: Identifiable {
    let id = UUID()
    let items: [Any]
}

// MARK: - Share round: the card as an image

/// What the share card prints, from a finished round's card (pure).
struct RoundShareSummary: Equatable {
    var courseName: String
    /// "SAT · OCT 23 · 2026".
    var dateText: String
    var playerName: String?
    var model: ScorecardModel
    var isTracked: Bool

    var score: Int? { model.total.score }
    /// "+7", "E", "−2"; nil without par.
    var toParText: String? { model.grossToPar.map(ScorecardText.toPar) }
    var playedCount: Int { model.columns.filter { $0.score != nil }.count }
    /// "18 HOLES · TRACKED" / "14 OF 18 HOLES · CASUAL".
    var holesLine: String {
        let holes = playedCount >= HoleScoring.holeRange.count ? "18 HOLES" : "\(playedCount) OF 18 HOLES"
        return "\(holes) · \(isTracked ? "TRACKED" : "CASUAL")"
    }

    /// PUTTS / GIR / FIR, each only when it has something to show.
    var stats: [(title: String, value: String, sub: String?)] {
        var out: [(String, String, String?)] = []
        if let putts = model.total.putts { out.append(("PUTTS", "\(putts)", nil)) }
        if model.columns.contains(where: { $0.gir != nil }) {
            out.append(("GIR", "\(model.girCount)", "OF \(playedCount)"))
        }
        if let hits = model.firHits, let of = model.firAnswered { out.append(("FIR", "\(hits)", "OF \(of)")) }
        return out
    }

    @MainActor
    static func make(round: Round) -> RoundShareSummary? {
        guard let card = try? ScorecardLoader.load(round: round, curatedCourseId: round.curatedCourseId) else {
            return nil
        }
        let name = (card.courseName ?? round.courseName).flatMap { $0.isEmpty ? nil : $0 } ?? "Golf round"
        let date = round.startedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
            .uppercased().replacingOccurrences(of: ",", with: " ·")
        let player = PlayerProfile.name
        return RoundShareSummary(courseName: name, dateText: date, playerName: player.isEmpty ? nil : player,
                                 model: card.model, isTracked: round.mode != .casual)
    }
}

/// Share round's image (1080 × 1350, 4:5 — a social feed post): the course,
/// the score, both nines with their birdie / bogey marks, PUTTS · GIR · FIR,
/// and the player. Always the light paper card. Laid out at 360 × 450 pt and
/// rendered at 3×.
struct RoundShareCard: View {
    let summary: RoundShareSummary

    static let size = CGSize(width: 360, height: 450)
    private let ink = CardInk.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("THE FAIRWAY LOGBOOK").tracking(1.4)
                Spacer()
                Text(summary.dateText).tracking(0.8)
            }
            .font(CardInk.mono(8))
            .foregroundStyle(CardInk.ink2)

            Text(summary.courseName)
                .font(.custom(AppFont.serifName, size: 30).weight(.bold).italic())
                .foregroundStyle(ink)
                .lineLimit(2)
                .minimumScaleFactor(0.6)

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(summary.score.map(String.init) ?? "—")
                    .font(CardInk.serif(72))
                    .foregroundStyle(ink)
                    .tabularNumerals()
                VStack(alignment: .leading, spacing: 2) {
                    if let toPar = summary.toParText {
                        Text(toPar).font(CardInk.serif(26)).foregroundStyle(CardInk.palette.red)
                    }
                    Text(summary.holesLine).font(CardInk.mono(8)).tracking(0.8).foregroundStyle(CardInk.ink2)
                }
                .padding(.bottom, 10)
            }

            VStack(spacing: 6) {
                nine(.front)
                nine(.back)
            }

            if !summary.stats.isEmpty {
                HStack(spacing: 6) {
                    ForEach(summary.stats, id: \.title) { stat in
                        VStack(spacing: 1) {
                            Text(stat.title).font(CardInk.mono(7)).foregroundStyle(CardInk.ink2)
                            Text(stat.value).font(CardInk.serif(20)).foregroundStyle(ink)
                            if let sub = stat.sub { Text(sub).font(CardInk.mono(7)).foregroundStyle(CardInk.ink2) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .overlay(Rectangle().strokeBorder(ink, lineWidth: 1))
                    }
                }
            }

            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                // No name in Profile: no empty PLAYER line.
                if let player = summary.playerName {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("PLAYER").font(CardInk.mono(7)).foregroundStyle(CardInk.ink2)
                        Text(player)
                            .font(CardInk.hand(20)).foregroundStyle(CardInk.graphite)
                            .frame(minWidth: 120, alignment: .leading)
                            .overlay(alignment: .bottom) { Rectangle().fill(ink).frame(height: 1) }
                    }
                }
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "flag.fill").font(.system(size: 9)).foregroundStyle(CardInk.palette.flag)
                    Text("FAIRWAY LOGBOOK").font(CardInk.mono(7)).tracking(1).foregroundStyle(CardInk.ink2)
                }
            }
        }
        .padding(18)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(CardInk.innerCard)
        .overlay(Rectangle().strokeBorder(ink, lineWidth: 1.5).padding(6))
        .overlay(Rectangle().strokeBorder(ink, lineWidth: 0.75).padding(9))
        .background(CardInk.palette.paper)
        .environment(\.colorScheme, .light)
    }

    /// HOLE / PAR / SCORE for one nine, plus OUT or IN.
    private func nine(_ nine: ScorecardNine) -> some View {
        let columns = summary.model.columns(nine)
        let totals = summary.model.totals(nine)
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(columns) { c in cell("\(c.number)", font: CardInk.serif(10), color: CardInk.palette.paper) }
                cell(nine.totalLabel, font: CardInk.mono(8), color: CardInk.palette.paper)
            }
            .background(ink)
            GridRow {
                ForEach(columns) { c in cell(c.par.map(String.init) ?? "", font: CardInk.mono(8), color: CardInk.ink2) }
                cell(totals.par.map(String.init) ?? "", font: CardInk.mono(8), color: CardInk.ink2)
            }
            GridRow {
                ForEach(columns) { c in
                    Group {
                        if c.isNotPlayed {
                            Text("NP").font(CardInk.mono(7)).foregroundStyle(CardInk.ink2)
                        } else if let score = c.score {
                            ScoreMarkView(score: score, mark: .mark(toPar: c.toPar), font: CardInk.hand(15), size: 20)
                        } else {
                            Text("")
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 28)
                }
                cell(totals.score.map(String.init) ?? "", font: CardInk.serif(13), color: ink, height: 28)
            }
        }
        .overlay(Rectangle().strokeBorder(ink, lineWidth: 1))
    }

    private func cell(_ text: String, font: Font, color: Color, height: CGFloat = 16) -> some View {
        Text(text).font(font).foregroundStyle(color)
            .lineLimit(1).minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, minHeight: height)
    }

    /// The card as a 1080 × 1350 PNG in the temporary directory.
    @MainActor
    static func renderPNG(_ summary: RoundShareSummary) -> URL? {
        let renderer = ImageRenderer(content: RoundShareCard(summary: summary))
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        let slug = summary.courseName.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(slug.isEmpty ? "round" : slug)-card.png")
        try? FileManager.default.removeItem(at: url)
        do { try data.write(to: url) } catch { return nil }
        return url
    }
}
