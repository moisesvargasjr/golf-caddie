import CoreLocation
import SwiftUI

// `ShotReviewRow` and `AddMissingShotSheet` live in HoleEditComponents.swift
// (shared with HoleDetailView).

/// Paper-styled hole-confirm sheet. Presented when the user taps "›" on the
/// hole pill mid-round: captures par, lets the user fix shot clubs / add
/// missing shots / log penalties, then confirms and advances the hole.
struct HoleReviewSheet: View {
    let hole: Hole
    let bag: [ClubID]
    /// When true, presented AFTER the hole was already confirmed (the
    /// glasses-advance retro-summary path added 2026-05-22). Swaps the
    /// masthead and CTA labels so it reads as "look at what just happened"
    /// rather than "decide to confirm." `onConfirm` is still the save+close
    /// callback — the caller is responsible for NOT calling
    /// `confirmHoleAndAdvance` again on it.
    var isRetro: Bool = false
    /// Green anchor for this hole (curated/local), used to classify putts and
    /// score confidence for the B7.3 "what we tracked" card. Nil when the course
    /// has no green anchor — the card still shows the count + putter-club putts.
    var greenCoordinate: CLLocationCoordinate2D? = nil
    let onConfirm: (Int?) -> Void
    let onCancel: () -> Void

    @Environment(\.palette) private var palette
    @AppStorage("units") private var unitsRaw: String = Units.yards.rawValue

    @State private var shots: [Shot] = []
    @State private var penalties: [Penalty] = []
    @State private var par: Int = 4
    @State private var hasPar: Bool = false
    @State private var showPenaltySheet = false
    @State private var showAddShotSheet = false
    @State private var showPinMap = false
    @State private var loadError: String?

    private var units: Units { Units(rawValue: unitsRaw) ?? .yards }

    // B7.3 — reconstruct the loaded shots live (green-split + confidence) so the
    // "what we tracked" card and per-row markers stay in sync as the golfer edits
    // clubs / adds shots in this same sheet.
    private var reconstruction: HoleReconstruction {
        // Phone-only (Path B) holes carry their split/confidence already; re-running
        // Path A's green-split would mis-classify a fallback pin dropped on the green
        // as a putt. Trust the persisted classification for reconstructed shots;
        // live-recompute Path A only for GPS-tracked shots.
        if isReconstructed {
            let rs = shots.sorted { $0.sequenceNumber < $1.sequenceNumber }
                .map { ReconstructedShot(shot: $0, isPutt: $0.isPutt, confidence: $0.confidence ?? 1.0) }
            return HoleReconstruction(shots: rs, enteredScore: nil)
        }
        return Reconstructor.reconstruct(shots: shots, green: greenCoordinate)
    }
    private var classifications: [UUID: ReconstructedShot] {
        Dictionary(uniqueKeysWithValues: reconstruction.shots.map { ($0.shot.id, $0) })
    }
    private var hasLocatedShots: Bool {
        shots.contains { $0.latitude != nil && $0.longitude != nil }
    }
    private var isReconstructed: Bool {
        shots.contains { $0.source == .reconstructed }
    }

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    navRow
                        .padding(.horizontal, 24)
                        .padding(.top, 18)

                    masthead
                        .padding(.horizontal, 24)
                        .padding(.top, 18)

                    if !shots.isEmpty {
                        HoleReconstructionCard(
                            reconstruction: reconstruction,
                            mode: isReconstructed ? .reconstructed : .tracked,
                            onAdjustPins: hasLocatedShots ? { showPinMap = true } : nil
                        )
                        .padding(.horizontal, 24)
                        .padding(.top, 22)
                    }

                    section("Par", content: parContent)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)

                    section("Shots (\(shots.count))", content: shotsContent)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)

                    section("Penalties (\(penalties.count))", content: penaltiesContent)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)

                    if missingClubsCount > 0 {
                        warning
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                    }

                    scoreBlock
                        .padding(.horizontal, 24)
                        .padding(.top, 24)

                    confirmButton
                        .padding(.horizontal, 24)
                        .padding(.top, 18)

                    if let loadError {
                        Text(loadError)
                            .font(AppFont.micro)
                            .tracking(1.2)
                            .foregroundStyle(palette.red)
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                    }

                    Spacer(minLength: 36)
                }
            }
        }
        .presentationBackground(palette.paper)
        .themedRoot()
        .sheet(isPresented: $showPenaltySheet) {
            PenaltySheet(
                onPick: { type in addPenalty(type: type) },
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
        .fullScreenCover(isPresented: $showPinMap) {
            HolePinMapSheet(
                shots: shots,
                holeID: hole.id,
                holeNumber: hole.holeNumber,
                onShotMoved: { shot, coord in moveShot(shot, to: coord) },
                onDone: { showPinMap = false }
            )
        }
        .task { reload() }
    }

    // MARK: - Top

    private var navRow: some View {
        HStack {
            Button {
                onCancel()
            } label: {
                Text("‹ CANCEL")
                    .font(AppFont.metadata)
                    .tracking(1.4)
                    .foregroundStyle(palette.ink)
            }
            Spacer()
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 4) {
            Stamp(text: isRetro ? "Hole summary" : "Confirm hole")
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("Hole")
                    .font(.custom(AppFont.serifName, size: 18).italic().weight(.bold))
                    .foregroundStyle(palette.ink2)
                Text("\(hole.holeNumber)")
                    .font(.custom(AppFont.serifName, size: 56).weight(.bold))
                    .tracking(-2)
                    .foregroundStyle(palette.ink)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Section helper

    @ViewBuilder
    private func section<Body: View>(_ title: String, @ViewBuilder content: () -> Body) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title.uppercased())
                    .font(AppFont.stamp)
                    .tracking(1.4)
                    .foregroundStyle(palette.ink3)
                Spacer()
                Rectangle().fill(palette.rule).frame(height: 1)
            }
            content()
        }
    }

    // MARK: - Par

    @ViewBuilder
    private func parContent() -> some View {
        Toggle(isOn: $hasPar) {
            Text("Set par for this hole")
                .font(AppFont.bodyLarge)
                .foregroundStyle(palette.ink)
        }
        .tint(palette.flag)

        if hasPar {
            Stepper(value: $par, in: 3...6) {
                Text("Par \(par)")
                    .font(AppFont.bodyLarge)
                    .italic()
                    .foregroundStyle(palette.ink)
            }
        }
    }

    // MARK: - Shots

    @ViewBuilder
    private func shotsContent() -> some View {
        if shots.isEmpty {
            Text("No shots recorded.")
                .font(AppFont.bodyLarge)
                .italic()
                .foregroundStyle(palette.ink3)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(shots.enumerated()), id: \.element.id) { idx, shot in
                    shotRow(idx: idx, shot: shot)
                }
            }
        }
        Button {
            showAddShotSheet = true
        } label: {
            HStack {
                Stamp(text: "+ Add Missing Shot")
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 6)

        if hasLocatedShots {
            Button {
                showPinMap = true
            } label: {
                HStack {
                    Stamp(text: "✎ Adjust pins on map")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
    }

    private func shotRow(idx: Int, shot: Shot) -> some View {
        let dMeters = distance(at: idx)
        let yardsLabel: String? = {
            if let m = dMeters {
                let f = units.format(yards: Int(Distance.yards(fromMeters: m).rounded()))
                return "\(f.value) \(f.unit)"
            }
            return shot.hadGPS ? nil : "manual"
        }()

        return HStack(spacing: 12) {
            Text((idx + 1).roman)
                .font(.custom(AppFont.serifName, size: 16).italic().weight(.bold))
                .foregroundStyle(palette.ink2)
                .frame(width: 36, alignment: .leading)

            Menu {
                ForEach(bag) { c in
                    Button(c.longName) { updateShotClub(shot, club: c) }
                }
                Divider()
                Button("(no club)", role: .destructive) { updateShotClub(shot, club: nil) }
            } label: {
                Text(shot.club?.longName ?? "tap to set club")
                    .font(AppFont.bodyLarge)
                    .italic(shot.club == nil)
                    .foregroundStyle(shot.club == nil ? palette.flag : palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // B7.3 classification marker: putts read muted; a low-confidence
            // full shot gets the amber "check" cue that the card refers to.
            if let cls = classifications[shot.id] {
                if cls.isPutt {
                    Stamp(text: "putt", color: palette.ink3)
                } else if cls.confidence < HoleReconstruction.lowConfidenceThreshold {
                    Stamp(text: "check", color: palette.flag)
                }
            }

            if let yardsLabel {
                Text(yardsLabel)
                    .font(AppFont.monoRow)
                    .foregroundStyle(palette.ink2)
                    .tabularNumerals()
            }

            Button(role: .destructive) {
                deleteShot(shot)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.ink3)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
    }

    // MARK: - Penalties

    @ViewBuilder
    private func penaltiesContent() -> some View {
        if penalties.isEmpty {
            Text("None.")
                .font(AppFont.bodyLarge)
                .italic()
                .foregroundStyle(palette.ink3)
        } else {
            VStack(spacing: 0) {
                ForEach(penalties) { penalty in
                    HStack {
                        Text(penalty.type.displayName)
                            .font(AppFont.bodyLarge)
                            .foregroundStyle(palette.ink)
                        Spacer()
                        Stamp(text: "+\(penalty.strokeCount)", color: palette.flag)
                        Button(role: .destructive) {
                            deletePenalty(penalty)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13))
                                .foregroundStyle(palette.ink3)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
                }
            }
        }
        Button {
            showPenaltySheet = true
        } label: {
            HStack {
                Stamp(text: "+ Add Penalty", color: palette.flag)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    // MARK: - Score

    private var scoreBlock: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("Score")
                .font(AppFont.sectionTitle)
                .foregroundStyle(palette.ink)
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(score)")
                    .font(.custom(AppFont.serifName, size: 48).weight(.bold))
                    .tracking(-1.5)
                    .foregroundStyle(palette.ink)
                    .tabularNumerals()
                if let label = scoreLabel {
                    Stamp(text: label, color: deltaColor)
                }
            }
        }
    }

    private var warning: some View {
        HStack {
            Stamp(text: "\(missingClubsCount) shot\(missingClubsCount == 1 ? "" : "s") missing club", color: palette.flag)
            Spacer()
        }
    }

    private var confirmButton: some View {
        Button {
            onConfirm(hasPar ? par : nil)
        } label: {
            HStack(spacing: 6) {
                Text(isRetro ? "Done" : "Confirm")
                    .font(AppFont.cta)
                    .italic()
                    .fontWeight(.regular)
                    .foregroundStyle(palette.paper.opacity(0.85))
                if !isRetro {
                    Text("hole")
                        .font(AppFont.cta)
                        .foregroundStyle(palette.paper)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(palette.ink)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: Color.black.opacity(0.25), radius: 0, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Computed

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
        case ..<(-2): return "\(-diff) UNDER"
        case -2: return "EAGLE"
        case -1: return "BIRDIE"
        case 0: return "PAR"
        case 1: return "BOGEY"
        case 2: return "DOUBLE BOGEY"
        case 3: return "TRIPLE BOGEY"
        case 4...: return "+\(diff)"
        default: return nil
        }
    }

    private var deltaColor: Color {
        guard hasPar else { return palette.ink }
        let diff = score - par
        return (diff < 0 || diff >= 2) ? palette.red : palette.ink
    }

    // MARK: - Data

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

    private func deleteShot(_ shot: Shot) {
        do {
            try ShotRepository.deleteAndRenumber(shot)
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

    // A hand-dragged pin: store the new location and drop the GPS accuracy. The
    // reconstructor reads a located-but-accuracyless shot as user-confirmed
    // (full confidence), so the amber "check" cue clears on reload.
    private func moveShot(_ shot: Shot, to coord: CLLocationCoordinate2D) {
        var updated = shot
        updated.latitude = coord.latitude
        updated.longitude = coord.longitude
        updated.hadGPS = true
        updated.gpsAccuracy = nil
        updated.confidence = 1.0 // user-placed = ground truth (also clears Path-B's amber flag)
        do {
            try ShotRepository.update(updated)
            reload()
        } catch {
            loadError = "Couldn't move shot: \(error.localizedDescription)"
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

// MARK: - Italic-conditional helper (shared with HoleDetailView)

private extension Text {
    func italic(_ on: Bool) -> Text { on ? self.italic() : self }
}
