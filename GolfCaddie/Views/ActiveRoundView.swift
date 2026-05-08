import SwiftUI

struct ActiveRoundView: View {
    let controller: RoundController
    let location: LocationManager
    let bag: [ClubID]

    @State private var isMarkingShot = false
    @State private var actionError: String?
    @State private var reviewingHole: Hole?
    @State private var showPenaltySheet = false
    @State private var endedRoundForReview: Round?
    @State private var battery = BatteryMonitor()
    @State private var batteryAtRoundStart: Float?
    @State private var showEndRoundConfirm = false
    @State private var showUndoConfirm = false

    var body: some View {
        Group {
            if controller.isActive {
                activeBody
            } else {
                idleBody
            }
        }
        .sheet(item: $endedRoundForReview) { round in
            NavigationStack {
                RoundReviewView(
                    round: round,
                    bag: bag,
                    onResume: { resumeRound(round) },
                    onDismiss: {
                        endedRoundForReview = nil
                        controller.clearMostRecentlyEndedRound()
                    }
                )
            }
        }
        .alert("End Round?", isPresented: $showEndRoundConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("End Round", role: .destructive) {
                performEndRound()
            }
        } message: {
            Text("Your round will be saved. You can resume it from the review screen if you change your mind.")
        }
        .alert("Undo last shot?", isPresented: $showUndoConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Undo", role: .destructive) {
                performUndoLastShot()
            }
        } message: {
            if let shot = controller.currentHoleShots.last {
                let label = shot.club?.longName ?? "no club"
                Text("Removes Shot \(shot.sequenceNumber) (\(label)) from this hole.")
            } else {
                Text("Removes the most recent shot.")
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
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text(holeLabel)
                    .font(.headline)
                gpsIndicator
                Spacer()
                Button("End Round", role: .destructive) {
                    showEndRoundConfirm = true
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.top, 4)

            ActiveRoundMap(
                location: location,
                shots: controller.currentHoleShots,
                lastMarkResult: controller.lastMarkResult,
                battery: battery,
                batteryDropSinceStart: batteryDrop
            )
            .frame(height: 280)
            .padding(.horizontal)

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
                            .font(.system(size: 28, weight: .heavy))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 100)
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

            HStack(spacing: 8) {
                Button {
                    showUndoConfirm = true
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .tint(.gray)
                .disabled(controller.currentHoleShots.isEmpty)

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
        if isFixStale { return .gray }
        switch location.fixQuality {
        case .none: return .gray
        case .degraded: return .orange
        case .acceptable: return .yellow
        case .good: return .green
        }
    }

    private var isFixStale: Bool {
        guard let timestamp = location.latestLocation?.timestamp else { return true }
        return Date().timeIntervalSince(timestamp) > 10
    }

    private var gpsAccuracyText: String {
        guard let loc = location.latestLocation, loc.horizontalAccuracy > 0 else {
            return "GPS no fix"
        }
        if isFixStale {
            return "GPS stale"
        }
        return "GPS ±\(Int(loc.horizontalAccuracy.rounded()))m"
    }

    private func startRound() {
        actionError = nil
        do {
            try controller.startRound()
            if battery.hasReading {
                batteryAtRoundStart = battery.level
            }
        } catch {
            actionError = "Couldn't start round: \(error.localizedDescription)"
        }
    }

    private func performEndRound() {
        actionError = nil
        let toReview = controller.currentRound
        do {
            try controller.endRound()
            endedRoundForReview = toReview
            batteryAtRoundStart = nil
        } catch {
            actionError = "Couldn't end round: \(error.localizedDescription)"
        }
    }

    private func performUndoLastShot() {
        actionError = nil
        do {
            try controller.removeLastShot()
        } catch {
            actionError = "Couldn't undo: \(error.localizedDescription)"
        }
    }

    private func resumeRound(_ round: Round) {
        actionError = nil
        do {
            try controller.resumeRound(round)
            endedRoundForReview = nil
            if battery.hasReading {
                batteryAtRoundStart = battery.level
            }
        } catch {
            actionError = "Couldn't resume: \(error.localizedDescription)"
        }
    }

    private var batteryDrop: Int? {
        guard let start = batteryAtRoundStart, battery.hasReading else { return nil }
        let drop = Int(((start - battery.level) * 100).rounded())
        return drop > 0 ? drop : nil
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
