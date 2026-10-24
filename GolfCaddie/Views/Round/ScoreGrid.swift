import SwiftUI

/// Casual Finish hole (canvas Casual / Folded-Casual / iPhone-Casual /
/// iPhone-Casual-Landscape): "Score on hole 8?", a 5 × 2 grid of 1–10+ with
/// the golf name under each cell, a putts row (0–4+), then NOT YET and
/// "Save 5 · hole 9 ›". In the side panel on the open Duo, book and iPhone
/// landscape; as the bottom sheet on folded and iPhone portrait. Also edits
/// a past casual hole (then the left button goes back to the live hole).
struct ScoreGrid: View {
    /// Sizes per presentation, from the boards.
    struct Metrics: Equatable {
        var titleSize: CGFloat
        var cellHeight: CGFloat
        var cellFont: CGFloat
        var nameFont: CGFloat
        var puttHeight: CGFloat
        var gap: CGFloat
        var spacing: CGFloat
        /// Width of the PUTTS label beside the row; nil puts it above.
        var puttsLabelWidth: CGFloat?
        var cancelWidth: CGFloat
        var buttonHeight: CGFloat
        var saveFont: CGFloat
        /// "Save 5 · next ›" instead of "Save 5 · hole 9 ›".
        var compactSave: Bool

        /// Side panel (open Duo, book).
        static let panel = Metrics(titleSize: 18, cellHeight: 48, cellFont: 17, nameFont: 7, puttHeight: 48,
                                   gap: 4, spacing: 8, puttsLabelWidth: nil, cancelWidth: 84,
                                   buttonHeight: 52, saveFont: 17, compactSave: false)
        /// iPhone landscape's shorter panel.
        static let tight = Metrics(titleSize: 15, cellHeight: 44, cellFont: 15, nameFont: 7, puttHeight: 44,
                                   gap: 4, spacing: 5, puttsLabelWidth: 44, cancelWidth: 84,
                                   buttonHeight: 44, saveFont: 16, compactSave: true)
        /// Bottom sheet (folded, iPhone portrait).
        static let sheet = Metrics(titleSize: 22, cellHeight: 56, cellFont: 18, nameFont: 8, puttHeight: 48,
                                   gap: 6, spacing: 10, puttsLabelWidth: 52, cancelWidth: 110,
                                   buttonHeight: 56, saveFont: 18, compactSave: true)
    }

    let model: RoundPanelModel
    let actions: RoundPanelActions
    var metrics: Metrics = .panel
    @Environment(\.palette) private var palette

    private var draft: ScoreGridDraft { model.scoreDraft }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing) {
            Text(ScoreGridModel.title(holeNumber: model.holeNumber))
                .font(RoundFont.serif(metrics.titleSize))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            LazyVGrid(columns: columns, spacing: metrics.gap) {
                ForEach(ScoreGridModel.scoreCells, id: \.self) { cell in scoreCell(cell) }
            }
            puttsRow
            buttons
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(InRoundAccessibilityID.scoreGrid)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: metrics.gap), count: 5)
    }

    // MARK: Cells

    private func scoreCell(_ cell: Int) -> some View {
        let selected = draft.isScoreSelected(cell)
        let name = ScoreGridModel.name(strokes: cell, par: model.par)
        return Button { actions.pickScore(cell) } label: {
            VStack(spacing: 1) {
                Text(ScoreGridModel.scoreLabel(cell)).font(RoundFont.mono(metrics.cellFont))
                // A blank line keeps every cell the same height.
                Text(name.isEmpty ? " " : name).font(RoundFont.mono(metrics.nameFont)).tracking(0.3)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .modifier(GridCellStyle(selected: selected, height: metrics.cellHeight))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ScoreGridModel.scoreAccessibilityLabel(cell, par: model.par))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(InRoundAccessibilityID.scoreCell(cell))
    }

    @ViewBuilder
    private var puttsRow: some View {
        if let width = metrics.puttsLabelWidth {
            HStack(spacing: metrics.gap) {
                puttsLabel.frame(width: width, alignment: .leading)
                ForEach(ScoreGridModel.puttCells, id: \.self) { cell in puttsCell(cell) }
            }
        } else {
            puttsLabel
            HStack(spacing: metrics.gap) {
                ForEach(ScoreGridModel.puttCells, id: \.self) { cell in puttsCell(cell) }
            }
        }
    }

    private var puttsLabel: some View {
        StampLabel(text: "PUTTS", size: 10).accessibilityHidden(true)
    }

    private func puttsCell(_ cell: Int) -> some View {
        let selected = draft.isPuttsSelected(cell)
        let available = draft.isPuttsAvailable(cell)
        return Button { actions.pickScorePutts(cell) } label: {
            Text(ScoreGridModel.puttsLabel(cell))
                .font(RoundFont.mono(17))
                .modifier(GridCellStyle(selected: selected, height: metrics.puttHeight))
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.35)
        .accessibilityLabel(ScoreGridModel.puttsAccessibilityLabel(cell))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(InRoundAccessibilityID.puttsCell(cell))
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack(spacing: metrics.gap + 2) {
            if model.question == .score {
                OutlineActionButton(title: "NOT YET", fontSize: 10, minHeight: metrics.buttonHeight,
                                    action: actions.cancelQuestion)
                    .frame(width: metrics.cancelWidth)
            } else if model.entryShowsBackToLive {
                OutlineActionButton(title: model.backToLiveShortTitle, fontSize: 9, minHeight: metrics.buttonHeight,
                                    action: actions.backToLive)
                    .frame(width: metrics.cancelWidth + 16)
                    .accessibilityIdentifier(InRoundAccessibilityID.backToLive)
            }
            saveButton
        }
    }

    private var saveButton: some View {
        let ready = draft.canSave
        let title = ScoreGridModel.saveTitle(strokes: draft.strokes, holeNumber: model.holeNumber,
                                             advances: model.scoreGridAdvances, compact: metrics.compactSave)
        return Button(action: actions.saveScore) {
            Text(title)
                .font(RoundFont.serif(metrics.saveFont))
                .foregroundStyle(ready ? palette.paper : palette.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: max(metrics.buttonHeight, RoundChromeMetrics.minTap))
                .background(ready ? palette.ink : palette.ink.opacity(0.15))
                .shadow(color: ready ? palette.cardShadow.color : .clear, radius: 0,
                        x: RoundChromeMetrics.shadow, y: RoundChromeMetrics.shadow)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .accessibilityLabel(ready ? title : "Pick a score first")
        .accessibilityIdentifier(InRoundAccessibilityID.saveScore)
    }
}

/// Filled ink when picked, ink outline otherwise (canvas grid cells).
private struct GridCellStyle: ViewModifier {
    let selected: Bool
    let height: CGFloat
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .foregroundStyle(selected ? palette.paper : palette.ink)
            .frame(maxWidth: .infinity, minHeight: max(height, RoundChromeMetrics.minTap))
            .background(selected ? palette.ink : Color.clear)
            .overlay {
                if !selected { Rectangle().strokeBorder(palette.ink, lineWidth: RoundChromeMetrics.rule) }
            }
            .contentShape(Rectangle())
    }
}
