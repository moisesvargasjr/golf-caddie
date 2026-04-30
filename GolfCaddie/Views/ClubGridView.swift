import SwiftUI

struct ClubGridView: View {
    let bag: [ClubID]
    let selectedClub: ClubID?
    let onSelect: (ClubID) -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 6),
        count: 7
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(bag) { club in
                ClubCell(
                    club: club,
                    isSelected: club == selectedClub
                )
                .onTapGesture {
                    onSelect(club)
                }
            }
        }
    }
}

private struct ClubCell: View {
    let club: ClubID
    let isSelected: Bool

    var body: some View {
        Text(club.shortName)
            .font(.body.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: isSelected ? 0 : 1)
            )
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var background: some View {
        if isSelected {
            Color.accentColor
        } else {
            Color(.secondarySystemBackground)
        }
    }
}

#Preview {
    ClubGridView(
        bag: ClubConfiguration.recommendedDefault.bag,
        selectedClub: .sevenIron
    ) { _ in }
    .padding()
}
