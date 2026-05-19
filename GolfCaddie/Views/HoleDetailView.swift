import CoreLocation
import SwiftUI

/// Combined previous-hole review + editor: navigate hole-by-hole, fix par on
/// any hole (incl. confirmed), restore a deleted stroke, drag a shot's pin to
/// correct its location, and (when the round matched a curated course) place
/// the hole's Tee/Green anchors and see distance-to-green.
///
/// Owns its own `holes` copy so par edits reflect immediately; every
/// persistence call also fires `onChanged` so `RoundReviewView` re-pulls the
/// canonical data when this view pops. Par writes go through
/// `HoleRepository.setPar` (this screen is reached for ended/reviewed rounds —
/// no live controller hole to sync). Captured anchors are LOCAL only; they're
/// exported later and merged into the curated catalog.
struct HoleDetailView: View {
    let bag: [ClubID]
    /// Curated course this round matched, or nil → anchor capture / yardage
    /// hidden (graceful degradation).
    let curatedCourseId: String?
    let onChanged: () -> Void

    @State private var holes: [Hole]
    @State private var index: Int
    @State private var shots: [Shot] = []
    @State private var penaltyCount: Int = 0
    @State private var hasPar: Bool = false
    @State private var par: Int = 4
    @State private var showAddShotSheet = false
    @State private var anchorsMode = false
    @State private var localAnchor: LocalCourseAnchor?
    @State private var curatedCourse: CuratedCourse?
    @State private var exportFile: ExportFile?
    @State private var loadError: String?

    init(
        holes: [Hole],
        bag: [ClubID],
        curatedCourseId: String? = nil,
        startIndex: Int = 0,
        onChanged: @escaping () -> Void
    ) {
        self.bag = bag
        self.curatedCourseId = curatedCourseId
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

    private var curatedHole: CuratedHole? {
        guard let hole else { return nil }
        return curatedCourse?.holes.first { $0.number == hole.holeNumber }
    }

    private func firstShotPoint() -> GeoPoint? {
        shots.first { $0.latitude != nil }
            .flatMap { s in s.latitude.flatMap { lat in s.longitude.map { GeoPoint(lat: lat, lng: $0) } } }
    }

    private func lastShotPoint() -> GeoPoint? {
        shots.last { $0.latitude != nil }
            .flatMap { s in s.latitude.flatMap { lat in s.longitude.map { GeoPoint(lat: lat, lng: $0) } } }
    }

    /// Pin shown for capture: local override → curated → a sensible seed
    /// (first/last GPS shot, else course centroid so there's always a
    /// draggable pin). Only surfaced in anchorsMode.
    private var displayTee: GeoPoint? {
        guard anchorsMode else { return nil }
        return localAnchor?.tee ?? curatedHole?.teeAnchor ?? firstShotPoint() ?? curatedCourse?.location
    }

    private var displayGreen: GeoPoint? {
        guard anchorsMode else { return nil }
        return localAnchor?.green ?? curatedHole?.greenAnchor ?? lastShotPoint() ?? curatedCourse?.location
    }

    /// Authoritative green for distance — a real captured/curated anchor
    /// only (never a shot-derived guess, which would be a meaningless yardage).
    private var effectiveGreen: GeoPoint? {
        localAnchor?.green ?? curatedHole?.greenAnchor
    }

    private var greenYards: Int? {
        guard let g = effectiveGreen, let from = lastShotPoint() else { return nil }
        let m = Distance.meters(
            from: CLLocationCoordinate2D(latitude: from.lat, longitude: from.lng),
            to: CLLocationCoordinate2D(latitude: g.lat, longitude: g.lng)
        )
        return Int(Distance.yards(fromMeters: m).rounded())
    }

    var body: some View {
        VStack(spacing: 0) {
            navHeader

            if let hole {
                EditableHoleMap(
                    shots: shots,
                    holeID: hole.id,
                    onShotMoved: { shot, coord in moveShot(shot, to: coord) },
                    tee: displayTee,
                    green: displayGreen,
                    onAnchorMoved: anchorsMode ? { kind, coord in
                        saveAnchor(kind, coord)
                    } : nil
                )
                .frame(height: 260)
                .overlay(alignment: .bottom) {
                    if anchorsMode {
                        Text("Drag the T (tee) and G (green) pins. Saved on this device.")
                            .font(.caption)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 8)
                    } else if !hasGPSShots {
                        Text("No GPS shots on this hole to place.")
                            .font(.caption)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 8)
                    }
                }

                Form {
                    parSection
                    if curatedCourseId != nil {
                        courseSection
                    }
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

    private var courseSection: some View {
        Section {
            Toggle("Place tee & green pins", isOn: $anchorsMode)
            if let yds = greenYards {
                LabeledContent("To green from last shot") {
                    Text("\(yds) yds").monospacedDigit()
                }
            }
            Button {
                exportAnchors()
            } label: {
                Label("Export anchors for this course", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Course setup")
        } footer: {
            Text("Anchors are saved on this device, then exported and merged into the shared course data later — that's what enables distance-to-green here and on the glasses.")
        }
        .sheet(item: $exportFile) { ShareSheet(url: $0.url) }
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
            if let courseId = curatedCourseId {
                curatedCourse = try? CourseDataRepository.course(byId: courseId)
                localAnchor = try? LocalAnchorRepository.anchor(
                    courseId: courseId, holeNumber: hole.holeNumber
                )
            } else {
                curatedCourse = nil
                localAnchor = nil
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

    private func saveAnchor(_ kind: LocalAnchorRepository.AnchorKind, _ coord: CLLocationCoordinate2D) {
        guard let courseId = curatedCourseId, let hole else { return }
        do {
            try LocalAnchorRepository.setPoint(
                courseId: courseId,
                holeNumber: hole.holeNumber,
                which: kind,
                point: GeoPoint(lat: coord.latitude, lng: coord.longitude)
            )
            localAnchor = try? LocalAnchorRepository.anchor(
                courseId: courseId, holeNumber: hole.holeNumber
            )
            onChanged()
        } catch {
            loadError = "Couldn't save anchor: \(error.localizedDescription)"
        }
    }

    private func exportAnchors() {
        guard let courseId = curatedCourseId else { return }
        do {
            let anchors = try LocalAnchorRepository.anchorsForCourse(courseId)
            let payload = AnchorExport(
                courseId: courseId,
                anchors: anchors.compactMap { a in
                    guard a.tee != nil || a.green != nil else { return nil }
                    return AnchorExport.HoleAnchors(
                        holeNumber: a.holeNumber,
                        teeAnchor: a.tee,
                        greenAnchor: a.green
                    )
                }
            )
            guard !payload.anchors.isEmpty else {
                loadError = "No anchors captured for this course yet."
                return
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(courseId)-anchors.json")
            try data.write(to: url, options: .atomic)
            exportFile = ExportFile(url: url)
        } catch {
            loadError = "Export failed: \(error.localizedDescription)"
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
