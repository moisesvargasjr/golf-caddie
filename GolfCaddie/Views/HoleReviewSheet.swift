import CoreLocation
import SwiftUI

// `ShotReviewRow` and `AddMissingShotSheet` now live in
// HoleEditComponents.swift (shared with HoleDetailView).

struct HoleReviewSheet: View {
    let hole: Hole
    let bag: [ClubID]
    let onConfirm: (Int?) -> Void
    let onCancel: () -> Void

    @State private var shots: [Shot] = []
    @State private var penalties: [Penalty] = []
    @State private var par: Int = 4
    @State private var hasPar: Bool = false
    @State private var showPenaltySheet = false
    @State private var showAddShotSheet = false
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Form {
                parSection
                shotsSection
                penaltiesSection
                scoreSection
                if missingClubsCount > 0 {
                    missingWarningSection
                }
                if let loadError {
                    Section {
                        Text(loadError)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Hole \(hole.holeNumber) Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Confirm") {
                        onConfirm(hasPar ? par : nil)
                    }
                    .fontWeight(.bold)
                }
            }
            .sheet(isPresented: $showPenaltySheet) {
                PenaltySheet(
                    onPick: { type in
                        addPenalty(type: type)
                    },
                    onCancel: { showPenaltySheet = false }
                )
            }
            .sheet(isPresented: $showAddShotSheet) {
                AddMissingShotSheet(
                    bag: bag,
                    currentShotCount: shots.count,
                    onAdd: { club, position in
                        addMissingShot(club: club, position: position)
                    },
                    onCancel: { showAddShotSheet = false }
                )
            }
        }
        .task { reload() }
    }

    private var parSection: some View {
        Section {
            Toggle("Set par for this hole", isOn: $hasPar)
            if hasPar {
                Stepper("Par: \(par)", value: $par, in: 3 ... 6)
            }
        }
    }

    private var shotsSection: some View {
        Section {
            if shots.isEmpty {
                Text("No shots recorded.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(shots.enumerated()), id: \.element.id) { idx, shot in
                    ShotReviewRow(
                        shot: shot,
                        bag: bag,
                        distanceMeters: distance(at: idx)
                    ) { newClub in
                        updateShotClub(shot, club: newClub)
                    }
                }
                .onDelete { offsets in
                    deleteShots(at: offsets)
                }
            }
            Button {
                showAddShotSheet = true
            } label: {
                Label("Add Missing Shot", systemImage: "plus.circle.fill")
            }
        } header: {
            HStack {
                Text("Shots (\(shots.count))")
                Spacer()
                if !shots.isEmpty {
                    Text("Swipe to delete")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textCase(nil)
                }
            }
        }
    }

    private var penaltiesSection: some View {
        Section("Penalties (\(penalties.count))") {
            ForEach(penalties) { penalty in
                HStack {
                    Text(penalty.type.displayName)
                    Spacer()
                    Text("+\(penalty.strokeCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button(role: .destructive) {
                        deletePenalty(penalty)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .tint(.red)
                }
            }
            Button {
                showPenaltySheet = true
            } label: {
                Label("Add Penalty", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var scoreSection: some View {
        Section {
            HStack {
                Text("Score").font(.title3.bold())
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(score)")
                        .font(.title.bold())
                        .monospacedDigit()
                    if let label = scoreLabel {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var missingWarningSection: some View {
        Section {
            Label(
                "\(missingClubsCount) shot\(missingClubsCount == 1 ? "" : "s") missing club",
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.orange)
        }
    }

    private var score: Int {
        shots.count + penalties.reduce(0) { $0 + $1.strokeCount }
    }

    private var missingClubsCount: Int {
        shots.filter { $0.club == nil }.count
    }

    private var scoreLabel: String? {
        guard hasPar else { return nil }
        let diff = score - par
        switch diff {
        case ..<(-2): return "\(-diff) Under"
        case -2: return "Eagle"
        case -1: return "Birdie"
        case 0: return "Par"
        case 1: return "Bogey"
        case 2: return "Double Bogey"
        case 3: return "Triple Bogey"
        case 4...: return "+\(diff)"
        default: return nil
        }
    }

    private func distance(at idx: Int) -> Double? {
        guard idx + 1 < shots.count else { return nil }
        let curr = shots[idx]
        let next = shots[idx + 1]
        guard let cLat = curr.latitude, let cLng = curr.longitude,
              let nLat = next.latitude, let nLng = next.longitude
        else { return nil }
        return Distance.meters(
            from: CLLocationCoordinate2D(latitude: cLat, longitude: cLng),
            to: CLLocationCoordinate2D(latitude: nLat, longitude: nLng)
        )
    }

    private func reload() {
        do {
            shots = try ShotRepository.shotsForHole(hole.id)
            penalties = try PenaltyRepository.penaltiesForHole(hole.id)
            if let p = hole.par {
                par = p
                hasPar = true
            } else {
                par = 4
                hasPar = false
            }
            loadError = nil
        } catch {
            loadError = "Failed to load: \(error.localizedDescription)"
        }
    }

    private func deleteShots(at offsets: IndexSet) {
        let toDelete = offsets.map { shots[$0] }
        do {
            for shot in toDelete {
                try ShotRepository.deleteAndRenumber(shot)
            }
            reload()
        } catch {
            loadError = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func updateShotClub(_ shot: Shot, club: ClubID?) {
        var updated = shot
        updated.club = club
        do {
            try ShotRepository.update(updated)
            reload()
        } catch {
            loadError = "Update failed: \(error.localizedDescription)"
        }
    }

    private func addPenalty(type: PenaltyType) {
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
            reload()
        } catch {
            loadError = "Add penalty failed: \(error.localizedDescription)"
        }
    }

    private func deletePenalty(_ penalty: Penalty) {
        do {
            try PenaltyRepository.delete(penalty)
            reload()
        } catch {
            loadError = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func addMissingShot(club: ClubID?, position: Int) {
        let shot = Shot(
            id: UUID(),
            holeID: hole.id,
            sequenceNumber: position,
            timestamp: Date(),
            latitude: nil,
            longitude: nil,
            gpsAccuracy: nil,
            hadGPS: false,
            club: club,
            source: .manual,
            notes: nil
        )
        do {
            try ShotRepository.insertShot(shot, at: position)
            showAddShotSheet = false
            reload()
        } catch {
            loadError = "Add shot failed: \(error.localizedDescription)"
        }
    }
}
