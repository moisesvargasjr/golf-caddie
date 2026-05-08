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
    @State private var mapFollowMode: Bool = true

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
        ActiveRoundMap(
            shots: controller.currentHoleShots,
            followMode: $mapFollowMode
        )
        .ignoresSafeArea()
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomPanel
        }
        .overlay(alignment: .topTrailing) {
            if !mapFollowMode {
                Button {
                    mapFollowMode = true
                } label: {
                    Label("Follow", systemImage: "location.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.trailing, 12)
                .padding(.top, 8)
            }
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

    private var topBar: some View {
        HStack(spacing: 12) {
            Text(holeLabel)
                .font(.headline)
            gpsIndicator
            Spacer()
            batteryBadge
            Button("End", role: .destructive) {
                showEndRoundConfirm = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private var bottomPanel: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(currentClubLabel)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(controller.currentClub == nil ? .secondary : .primary)
                Spacer()
                Text("\(controller.shotsInCurrentHole) shot\(controller.shotsInCurrentHole == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if case let .success(_, accuracy) = controller.lastMarkResult, let accuracy {
                    Text(String(format: "Last ±%.1fm", accuracy))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button(action: markShot) {
                Group {
                    if isMarkingShot {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    } else {
                        Text("MARK SHOT")
                            .font(.system(size: 26, weight: .heavy))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 90)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isMarkingShot)

            ClubGridView(
                bag: bag,
                selectedClub: controller.currentClub
            ) { club in
                controller.setCurrentClub(club)
            }

            HStack(spacing: 8) {
                Button {
                    showUndoConfirm = true
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .tint(.gray)
                .controlSize(.small)
                .disabled(controller.currentHoleShots.isEmpty)

                Button {
                    showPenaltySheet = true
                } label: {
                    Label("Penalty", systemImage: "exclamationmark.triangle.fill")
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .controlSize(.small)

                Spacer()

                Button {
                    reviewingHole = controller.currentHole
                } label: {
                    Label("Next Hole", systemImage: "arrow.right.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            errorBanner
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var batteryBadge: some View {
        if let percent = battery.percent {
            HStack(spacing: 4) {
                Image(systemName: battery.iconName)
                    .foregroundStyle(batteryColor(percent: percent))
                Text("\(percent)%")
                if let drop = batteryDrop {
                    Text("(-\(drop)%)")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption.weight(.medium))
            .monospacedDigit()
        }
    }

    private func batteryColor(percent: Int) -> Color {
        if percent <= 15 { return .red }
        if percent <= 25 { return .orange }
        return .primary
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
            mapFollowMode = true
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
            mapFollowMode = true
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
