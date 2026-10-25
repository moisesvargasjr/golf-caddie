import SwiftUI

/// Strokes + putts for a hole that wasn't tracked, opened from a card's ADD
/// (or "Edit hole n score") — the entry panel from the iPhone-PastHole
/// mockup, as a sheet over the card.
struct HandScoreEntrySheet: View {
    let startingHole: Int?
    /// Saves the draft; returns an error message to show, or nil on success.
    let onSave: (HandScoreDraft) -> String?
    let onCancel: () -> Void

    @State private var draft: HandScoreDraft
    @State private var errorText: String?

    init(draft: HandScoreDraft, startingHole: Int?,
         onSave: @escaping (HandScoreDraft) -> String?, onCancel: @escaping () -> Void) {
        self.startingHole = startingHole
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: draft)
    }

    private let ink = CardInk.ink
    private static let stepper: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Score for hole \(draft.holeNumber)")
                .font(CardInk.serif(20))
                .foregroundStyle(ink)
                .accessibilityAddTraits(.isHeader)
            if let note {
                Text(note)
                    .font(CardInk.mono(10)).tracking(0.6)
                    .foregroundStyle(CardInk.palette.red)
            }
            stepperRow("STROKES", value: draft.strokes, unit: ScorecardText.strokes(draft.strokes),
                       id: "strokes",
                       minus: Step(label: "One fewer stroke", enabled: draft.canDecrementStrokes) {
                           draft = draft.decrementingStrokes()
                       },
                       plus: Step(label: "One more stroke", enabled: draft.canIncrementStrokes) {
                           draft = draft.incrementingStrokes()
                       })
            stepperRow("PUTTS", value: draft.putts, unit: ScorecardText.putts(draft.putts),
                       id: "putts",
                       minus: Step(label: "One fewer putt", enabled: draft.canDecrementPutts) {
                           draft = draft.decrementingPutts()
                       },
                       plus: Step(label: "One more putt", enabled: draft.canIncrementPutts) {
                           draft = draft.incrementingPutts()
                       })
            Text(draft.summary)
                .font(CardInk.mono(11))
                .foregroundStyle(CardInk.ink2)
                .accessibilityIdentifier("handScore.summary")
            if let errorText {
                Text(errorText)
                    .font(CardInk.mono(10))
                    .foregroundStyle(CardInk.palette.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button(action: onCancel) {
                    Text("BACK TO CARD")
                        .font(CardInk.mono(10))
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .overlay(Rectangle().strokeBorder(ink, lineWidth: 1.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("handScore.cancel")
                ScorecardFilledButton(title: "Save hole \(draft.holeNumber)", fontSize: 18,
                                      minHeight: 52, expands: true) {
                    errorText = onSave(draft)
                }
                .accessibilityIdentifier("handScore.save")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: 480, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CardInk.palette.paper.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .presentationDetents([.height(400), .large])
        .presentationBackground(CardInk.palette.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("handScore.sheet")
    }

    /// "NOT TRACKED · YOU STARTED ON HOLE 7" for a pre-start hole.
    private var note: String? {
        guard let startingHole, draft.holeNumber < startingHole else { return nil }
        return "NOT TRACKED · YOU STARTED ON HOLE \(startingHole)"
    }

    private struct Step {
        let label: String
        let enabled: Bool
        let action: () -> Void
    }

    private func stepperRow(_ title: String, value: Int, unit: String, id: String,
                            minus: Step, plus: Step) -> some View {
        HStack {
            Text(title)
                .font(CardInk.mono(11))
                .foregroundStyle(CardInk.ink2)
                .accessibilityHidden(true)
            Spacer()
            HStack(spacing: 10) {
                stepButton("−", minus).accessibilityIdentifier("handScore.\(id).minus")
                Text("\(value)")
                    .font(CardInk.serif(32))
                    .foregroundStyle(ink)
                    .tabularNumerals()
                    .frame(width: 44)
                    .accessibilityLabel(unit)
                    .accessibilityIdentifier("handScore.\(id).value")
                stepButton("+", plus).accessibilityIdentifier("handScore.\(id).plus")
            }
        }
    }

    private func stepButton(_ glyph: String, _ step: Step) -> some View {
        Button(action: step.action) {
            Text(glyph)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(step.enabled ? ink : ink.opacity(0.3))
                .frame(width: Self.stepper, height: Self.stepper)
                .overlay(Rectangle().strokeBorder(step.enabled ? ink : ink.opacity(0.3), lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!step.enabled)
        .accessibilityLabel(step.label)
    }
}
