import CoreLocation
import SwiftUI

/// Combined previous-hole review + editor: navigate hole-by-hole, fix par on
/// any hole (incl. confirmed), restore a deleted stroke, and drag a shot's
/// pin on the satellite map to correct its location.
///
/// Owns its own `holes` copy so par edits reflect immediately; every
/// persistence call also fires `onChanged` so the parent `RoundReviewView`
/// re-pulls the canonical data when this view pops. Par writes go straight to
/// `HoleRepository.setPar` (repo path) — this screen is reached for
/// ended/reviewed rounds, so there is no live controller hole to keep in
/// sync; `RoundController.setPar` exists for any future active-round entry.
struct HoleDetailView: View {
    let bag: [ClubID]
    let onChanged: () -> Void

    @State private var holes: [Hole]
    @State private var index: Int
    @State private var shots: [Shot] = []
    @State private var penaltyCount: Int = 0
    @State private var hasPar: Bool = false
    @State private var par: Int = 4
    @State private var showAddShotSheet = false
    @State private var loadError: String?

    init(
        holes: [Hole],
        bag: [ClubID],
        startIndex: Int = 0,
        onChanged: @escaping () -> Void
    ) {
        self.bag = bag
        self.onChanged = onChanged
        _holes = State(initialValue: holes)
        _index = State(initialValue: min(max(0, startIndex), max(0, holes.count - 1)))
    }

    private var hole: Hole? {
        holes.indices.contains(index) ? holes[index] : nil
    }

    private var hasGPSShots: Bool {
        shots.contains { $0.latitude != nil && $0.longitude != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            navHeader

            if let hole {
                EditableHoleMap(
                    shots: shots,
                    holeID: hole.id,
                    onShotMoved: { shot, coord in moveShot(shot, to: coord) }
                )
                .frame(height: 260)
                .overlay(alignment: .bottom) {
                    if !hasGPSShots {
                        Text("No GPS shots on this hole to place.")
                            .font(.caption)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 8)
                    }
                }

                Form {
                    parSection
                    shotsSection
                    if penaltyCount > 0 {
                        Section {
                            Text("\(penaltyCount) penalty stroke\(penaltyCount == 1 ? "" : "s") on this hole")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let loadError {
                        Section {
                            Text(loadError).foregroundStyle(.red).font(.caption)
                        }
                    }
                }
            } else {
                Spacer()
                Text("No holes to show.").foregroundStyle(.secondary)
                Spacer()
            }
        }
        .navigationTitle(hole.map { "Hole \($0.holeNumber)" } ?? "Hole")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: index) { loadHole() }
        .sheet(isPresented: $showAddShotSheet) {
            AddMissingShotSheet(
                bag: bag,
                currentShotCount: shots.count,
                onAdd: { club, position in addMissingShot(club: club, position: position) },
                onCancel: { showAddShotSheet = false }
            )
        }
    }

    private var navHeader: some View {
        HStack {
            Button {
                if index > 0 { index -= 1 }
            } label: {
                Image(systemName: "chevron.left").font(.title3.weight(.semibold))
            }
            .disabled(index == 0)

            Spacer()

            VStack(spacing: 2) {
                Text(hole.map { "Hole \($0.holeNumber)" } ?? "—")
                    .font(.headline)
                if let hole, hole.confirmedAt != nil {
                    Text("Confirmed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                if index < holes.count - 1 { index += 1 }
            } label: {
                Image(systemName: "chevron.right").font(.title3.weight(.semibold))
            }
            .disabled(index >= holes.count - 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var parSection: some View {
        Section {
            Toggle("Set par for this hole", isOn: $hasPar)
            if hasPar {
                Stepper("Par: \(par)", value: $par, in: 3 ... 6)
            }
        } footer: {
            Text("Editing par here updates this hole without re-confirming it.")
        }
        .onChange(of: hasPar) { _, _ in savePar() }
        .onChange(of: par) { _, _ in savePar() }
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
                .onDelete { offsets in deleteShots(at: offsets) }
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
                    Text("Swipe to delete · tap a pin then drag to fix")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textCase(nil)
                }
            }
        }
    }

    private func loadHole() {
        guard let hole else { return }
        do {
            shots = try ShotRepository.shotsForHole(hole.id)
            penaltyCount = try PenaltyRepository.penaltiesForHole(hole.id).count
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

    private func savePar() {
        guard let hole else { return }
        let newPar = hasPar ? par : nil
        guard newPar != hole.par else { return }
        do {
            try HoleRepository.setPar(holeID: hole.id, par: newPar)
            holes[index].par = newPar
            onChanged()
        } catch {
            loadError = "Couldn't save par: \(error.localizedDescription)"
        }
    }

    private func moveShot(_ shot: Shot, to coord: CLLocationCoordinate2D) {
        var updated = shot
        updated.latitude = coord.latitude
        updated.longitude = coord.longitude
        // A hand-placed point is intentional, not a GPS fix: mark it as
        // located, with no accuracy figure. Source is left unchanged.
        updated.hadGPS = true
        updated.gpsAccuracy = nil
        do {
            try ShotRepository.update(updated)
            loadHole()
            onChanged()
        } catch {
            loadError = "Couldn't move shot: \(error.localizedDescription)"
        }
    }

    private func updateShotClub(_ shot: Shot, club: ClubID?) {
        var updated = shot
        updated.club = club
        do {
            try ShotRepository.update(updated)
            loadHole()
            onChanged()
        } catch {
            loadError = "Update failed: \(error.localizedDescription)"
        }
    }

    private func deleteShots(at offsets: IndexSet) {
        let toDelete = offsets.map { shots[$0] }
        do {
            for shot in toDelete {
                try ShotRepository.deleteAndRenumber(shot)
            }
            loadHole()
            onChanged()
        } catch {
            loadError = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func addMissingShot(club: ClubID?, position: Int) {
        guard let hole else { return }
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
            loadHole()
            onChanged()
        } catch {
            loadError = "Add shot failed: \(error.localizedDescription)"
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
}
