import SwiftUI

struct ActiveRoundView: View {
    let controller: RoundController
    let location: LocationManager
    let bag: [ClubID]

    @State private var isMarkingShot = false
    @State private var actionError: String?
    @State private var reviewingHole: Hole?
    @State private var showPenaltySheet = false

    var body: some View {
        Group {
            if controller.isActive {
                activeBody
            } else {
                idleBody
            }
        }
    }

    private var idleBody: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "figure.golf")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text("Ready to play?")
                    .font(.title)
                    .fontWeight(.semibold)
                Text("Start a round to begin tracking shots.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: startRound) {
                Text("Start Round")
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            errorBanner
                .padding(.bottom, 8)
        }
    }

    private var activeBody: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center) {
                gpsIndicator
                Spacer()
                Button("End Round", role: .destructive, action: endRound)
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(holeLabel)
                    .font(.title3.bold())
                Text("Shots: \(controller.shotsInCurrentHole)")
                    .foregroundStyle(.secondary)
                if let last = controller.lastMarkResult {
                    Text(lastResultText(last))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            Spacer()

            Text(currentClubLabel)
                .font(.callout)
                .foregroundStyle(controller.currentClub == nil ? .secondary : .primary)
                .padding(.horizontal)

            Button(action: markShot) {
                Group {
                    if isMarkingShot {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    } else {
                        Text("MARK SHOT")
                            .font(.system(size: 32, weight: .heavy))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isMarkingShot)
            .padding(.horizontal)

            ClubGridView(
                bag: bag,
                selectedClub: controller.currentClub
            ) { club in
                controller.setCurrentClub(club)
            }
            .padding(.horizontal)

            HStack {
                Button {
                    showPenaltySheet = true
                } label: {
                    Label("Penalty", systemImage: "exclamationmark.triangle.fill")
                }
                .buttonStyle(.bordered)
                .tint(.orange)

                Spacer()

                Button {
                    reviewingHole = controller.currentHole
                } label: {
                    Label("Next Hole", systemImage: "arrow.right.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            errorBanner
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .sheet(item: $reviewingHole) { hole in
            HoleReviewSheet(
                hole: hole,
                bag: bag,
                onConfirm: { par in
                    confirmHole(par: par)
                },
                onCancel: {
                    reviewingHole = nil
                }
            )
        }
        .sheet(isPresented: $showPenaltySheet) {
            PenaltySheet(
                onPick: { type in
                    addPenaltyToCurrentHole(type: type)
                },
                onCancel: {
                    showPenaltySheet = false
                }
            )
        }
    }

    private var currentClubLabel: String {
        if let club = controller.currentClub {
            return "Current: \(club.longName)"
        }
        return "Current: tap a club below"
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let actionError {
            Text(actionError)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var holeLabel: String {
        if let hole = controller.currentHole {
            return "Hole \(hole.holeNumber)"
        }
        return "Hole 1"
    }

    private var gpsIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(gpsColor)
                .frame(width: 12, height: 12)
            Text(gpsAccuracyText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var gpsColor: Color {
        switch location.fixQuality {
        case .none: return .gray
        case .degraded: return .orange
        case .acceptable: return .yellow
        case .good: return .green
        }
    }

    private var gpsAccuracyText: String {
        guard let loc = location.latestLocation, loc.horizontalAccuracy > 0 else {
            return "GPS no fix"
        }
        return "GPS ±\(Int(loc.horizontalAccuracy.rounded()))m"
    }

    private func lastResultText(_ result: RoundController.ShotMarkResult) -> String {
        switch result {
        case let .success(_, accuracy):
            if let accuracy {
                return String(format: "Last shot: ±%.1fm", accuracy)
            }
            return "Last shot: no GPS"
        case let .failed(reason):
            return "Last shot failed: \(reason)"
        }
    }

    private func startRound() {
        actionError = nil
        do {
            try controller.startRound()
        } catch {
            actionError = "Couldn't start round: \(error.localizedDescription)"
        }
    }

    private func endRound() {
        actionError = nil
        do {
            try controller.endRound()
        } catch {
            actionError = "Couldn't end round: \(error.localizedDescription)"
        }
    }

    private func markShot() {
        actionError = nil
        Task {
            isMarkingShot = true
            do {
                try await controller.markShot()
            } catch {
                actionError = "Mark failed: \(error.localizedDescription)"
            }
            isMarkingShot = false
        }
    }

    private func confirmHole(par: Int?) {
        actionError = nil
        do {
            try controller.confirmHoleAndAdvance(par: par)
            reviewingHole = nil
        } catch {
            actionError = "Couldn't advance hole: \(error.localizedDescription)"
        }
    }

    private func addPenaltyToCurrentHole(type: PenaltyType) {
        actionError = nil
        guard let hole = controller.currentHole else {
            showPenaltySheet = false
            return
        }
        let penalty = Penalty(
            id: UUID(),
            holeID: hole.id,
            type: type,
            strokeCount: 1,
            timestamp: Date(),
            notes: nil
        )
        do {
            try PenaltyRepository.insert(penalty)
            showPenaltySheet = false
        } catch {
            actionError = "Add penalty failed: \(error.localizedDescription)"
        }
    }
}
