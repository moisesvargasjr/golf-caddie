import SwiftUI

struct RoundListView: View {
    let bag: [ClubID]

    @State private var rounds: [Round] = []
    @State private var loadError: String?

    var body: some View {
        List {
            if rounds.isEmpty && loadError == nil {
                Text("No rounds yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(rounds) { round in
                NavigationLink {
                    RoundReviewView(round: round, bag: bag)
                } label: {
                    RoundRow(round: round)
                }
            }
            if let loadError {
                Text(loadError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .navigationTitle("Rounds")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
    }

    private func reload() {
        do {
            rounds = try RoundRepository.allRounds()
            loadError = nil
        } catch {
            loadError = "Failed: \(error.localizedDescription)"
        }
    }
}

private struct RoundRow: View {
    let round: Round

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(round.startedAt, format: .dateTime.month().day().year().hour().minute())
                    .font(.callout)
                if let endedAt = round.endedAt {
                    Text("Duration: \(formatDuration(endedAt.timeIntervalSince(round.startedAt)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("In progress")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let totalMinutes = Int(s / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
