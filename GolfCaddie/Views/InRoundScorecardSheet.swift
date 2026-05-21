import SwiftUI

/// Mid-round read-only scorecard, presented from the Active Round screen's
/// "CARD" stamp. Shows score-so-far per confirmed hole + the in-progress
/// current hole. Tap a confirmed hole's cell to jump into HoleDetailView for
/// post-confirm edits.
struct InRoundScorecardSheet: View {
    let round: Round
    let currentHoleNumber: Int
    let onDismiss: () -> Void

    @Environment(\.palette) private var palette

    @State private var holes: [Hole] = []
    @State private var shotsByHole: [UUID: Int] = [:]
    @State private var penaltiesByHole: [UUID: Int] = [:]
    @State private var loadError: String?

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    navRow
                        .padding(.horizontal, 24)
                        .padding(.top, 18)

                    masthead
                        .padding(.horizontal, 24)
                        .padding(.top, 18)

                    totals
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                    if holes.contains(where: { $0.holeNumber <= 9 }) {
                        scorecardTable(title: "Front nine.", range: 1...9)
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                    }
                    if holes.contains(where: { $0.holeNumber >= 10 }) {
                        scorecardTable(title: "Back nine.", range: 10...18)
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                    }

                    if let loadError {
                        Text(loadError)
                            .font(AppFont.micro)
                            .tracking(1.2)
                            .foregroundStyle(palette.red)
                            .padding(.horizontal, 24)
                            .padding(.top, 12)
                    }

                    Spacer(minLength: 40)
                }
            }
        }
        .presentationBackground(palette.paper)
        .themedRoot()
        .onAppear { reload() }
    }

    private var navRow: some View {
        HStack {
            Button {
                onDismiss()
            } label: {
                Text("‹ CLOSE")
                    .font(AppFont.metadata)
                    .tracking(1.4)
                    .foregroundStyle(palette.ink)
            }
            Spacer()
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 4) {
            Stamp(text: "In progress")
            Text("Card so far.")
                .font(AppFont.sectionTitle)
                .foregroundStyle(palette.ink)
                .padding(.top, 6)
        }
    }

    private var totals: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("THROUGH \(confirmedCount)")
                    .font(AppFont.stamp)
                    .tracking(1.4)
                    .foregroundStyle(palette.ink3)
                Text("\(totalScore)")
                    .font(.custom(AppFont.serifName, size: 64).weight(.bold))
                    .tracking(-2.5)
                    .foregroundStyle(palette.ink)
                    .tabularNumerals()
            }
            Spacer()
            if let delta = totalDelta {
                Stamp(text: delta > 0 ? "+\(delta)" : (delta == 0 ? "E" : "\(delta)"),
                      color: delta > 0 ? palette.red : palette.ink)
            }
        }
    }

    private func scorecardTable(title: String, range: ClosedRange<Int>) -> some View {
        let rowHoles = holes.filter { range.contains($0.holeNumber) }
        let rowPar = rowHoles.reduce(0) { $0 + ($1.par ?? 0) }
        let rowShots = rowHoles.reduce(0) { $0 + holeScore($1) }
        let isFront = range.lowerBound == 1
        let summaryLabel = isFront ? "OUT" : "IN"

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(palette.ink)
                Spacer()
                Text("\(summaryLabel) \(rowShots)")
                    .font(AppFont.metadata)
                    .tracking(1.2)
                    .foregroundStyle(palette.ink2)
                    .tabularNumerals()
            }

            VStack(spacing: 0) {
                headerRow(range: range, summaryLabel: summaryLabel)
                parRow(range: range, total: rowPar)
                youRow(range: range, total: rowShots)
            }
        }
    }

    private func headerRow(range: ClosedRange<Int>, summaryLabel: String) -> some View {
        HStack(spacing: 0) {
            cell("HOLE", style: .header, align: .leading)
            ForEach(Array(range), id: \.self) { n in
                cell("\(n)", style: .header, align: .center)
            }
            cell(summaryLabel, style: .header, align: .trailing)
        }
        .overlay(alignment: .top) { Rectangle().fill(palette.ink).frame(height: 2) }
        .overlay(alignment: .bottom) { Rectangle().fill(palette.ink).frame(height: 1) }
    }

    private func parRow(range: ClosedRange<Int>, total: Int) -> some View {
        HStack(spacing: 0) {
            cell("PAR", style: .label, align: .leading)
            ForEach(Array(range), id: \.self) { n in
                if let hole = holes.first(where: { $0.holeNumber == n }), let par = hole.par {
                    cell("\(par)", style: .label, align: .center)
                } else {
                    cell("—", style: .label, align: .center)
                }
            }
            cell("\(total)", style: .label, align: .trailing)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
    }

    private func youRow(range: ClosedRange<Int>, total: Int) -> some View {
        HStack(spacing: 0) {
            cell("YOU", style: .label, align: .leading)
            ForEach(Array(range), id: \.self) { n in
                if let hole = holes.first(where: { $0.holeNumber == n }) {
                    let score = holeScore(hole)
                    let isCurrent = hole.holeNumber == currentHoleNumber
                    Group {
                        if let par = hole.par, hole.confirmedAt != nil {
                            ScoreBadge(score: score, par: par)
                        } else if isCurrent {
                            // In-progress current hole — show running score in flag color.
                            Text(score > 0 ? "\(score)" : "·")
                                .font(.custom(AppFont.monoName, size: 13).weight(.bold))
                                .foregroundStyle(palette.flag)
                                .tabularNumerals()
                        } else {
                            Text("·")
                                .font(.custom(AppFont.monoName, size: 13).weight(.bold))
                                .foregroundStyle(palette.ink3)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                } else {
                    Text("·")
                        .font(.custom(AppFont.monoName, size: 13).weight(.bold))
                        .foregroundStyle(palette.ink3)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                }
            }
            Text("\(total)")
                .font(.custom(AppFont.monoName, size: 16).weight(.bold))
                .foregroundStyle(palette.ink)
                .tabularNumerals()
                .frame(width: 44, alignment: .trailing)
        }
    }

    private enum CellStyle { case header, label }

    private func cell(_ text: String, style: CellStyle, align: Alignment) -> some View {
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

    // MARK: - Computed

    private var confirmedCount: Int {
        holes.filter { $0.confirmedAt != nil }.count
    }

    private func holeScore(_ hole: Hole) -> Int {
        (shotsByHole[hole.id] ?? 0) + (penaltiesByHole[hole.id] ?? 0)
    }

    private var totalScore: Int {
        holes.reduce(0) { $0 + holeScore($1) }
    }

    private var totalDelta: Int? {
        let pars = holes.compactMap { $0.par }
        guard !pars.isEmpty else { return nil }
        return totalScore - pars.reduce(0, +)
    }

    // MARK: - Data

    private func reload() {
        do {
            holes = try HoleRepository.holesForRound(round.id)
                .sorted { $0.holeNumber < $1.holeNumber }
            var sMap: [UUID: Int] = [:]
            var pMap: [UUID: Int] = [:]
            for hole in holes {
                sMap[hole.id] = (try? ShotRepository.shotsForHole(hole.id).count) ?? 0
                pMap[hole.id] = ((try? PenaltyRepository.penaltiesForHole(hole.id)) ?? [])
                    .reduce(0) { $0 + $1.strokeCount }
            }
            shotsByHole = sMap
            penaltiesByHole = pMap
            loadError = nil
        } catch {
            loadError = "Failed to load: \(error.localizedDescription)"
        }
    }
}
