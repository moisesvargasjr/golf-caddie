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

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @AppStorage("units") private var unitsRaw: String = Units.yards.rawValue

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
    @State private var isExpanded: Bool = false
    /// First-putt UUID of each putt-run the user has chosen to expand inline.
    /// Display-only state; not persisted. Resets on view re-instantiation
    /// (i.e. when the user opens a different round) — the default for every
    /// run is collapsed.
    @State private var expandedPuttRuns: Set<UUID> = []

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

    // MARK: - Computed properties (data shape unchanged)

    private var units: Units { Units(rawValue: unitsRaw) ?? .yards }

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

    private var displayTee: GeoPoint? {
        guard anchorsMode else { return nil }
        return localAnchor?.tee ?? curatedHole?.teeAnchor ?? firstShotPoint() ?? curatedCourse?.location
    }

    private var displayGreen: GeoPoint? {
        guard anchorsMode else { return nil }
        return localAnchor?.green ?? curatedHole?.greenAnchor ?? lastShotPoint() ?? curatedCourse?.location
    }

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

    private var score: Int { shots.count + penaltyCount }

    private var delta: Int? {
        guard let p = hole?.par else { return nil }
        return score - p
    }

    private var statusLabel: String {
        guard let d = delta else { return "—" }
        switch d {
        case ..<(-2): return "DOUBLE EAGLE"
        case -2: return "EAGLE"
        case -1: return "BIRDIE"
        case 0: return "PAR"
        case 1: return "BOGEY"
        case 2: return "DOUBLE BOGEY"
        case 3: return "TRIPLE BOGEY"
        case 4: return "QUAD"
        default: return "+\(d)"
        }
    }

    private var statusIsRed: Bool {
        if let d = delta { return d < 0 || d >= 2 }
        return false
    }

    /// Derived lie label — returns nil when there's no real signal to show.
    /// The Shot model has no `lie` field, so we only label the cases we can
    /// honestly infer: HOLE = the last shot of a confirmed hole (holed out);
    /// GREEN = within ~10yd of the green anchor (curated/local) OR the shot
    /// was a putt (you have to be on/near the green to use a putter — the
    /// Texas-wedge edge case is rare enough to ignore). Anything else returns
    /// nil; the row renders "—" so we stop pretending every shot was from the
    /// fairway. A future stored `lie` field is the real upgrade path.
    private func lie(for shot: Shot, at idx: Int) -> String? {
        let isLast = idx == shots.count - 1
        if isLast, hole?.confirmedAt != nil {
            return "HOLE"
        }
        if shot.club == .putter {
            return "GREEN"
        }
        if let g = effectiveGreen, let lat = shot.latitude, let lng = shot.longitude {
            let m = Distance.meters(
                from: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                to: CLLocationCoordinate2D(latitude: g.lat, longitude: g.lng)
            )
            let yds = Distance.yards(fromMeters: m)
            if yds < 10 { return "GREEN" }
        }
        return nil
    }

    /// Display-only grouping of the raw `shots` array: each entry is either
    /// one regular shot or a run of consecutive putts. Drives the ledger so a
    /// long string of tap-in putts collapses to one row instead of N. The
    /// Shot rows themselves are unchanged on disk — this is purely how we
    /// render them. A run can be tapped to expand inline; see
    /// `expandedPuttRuns`.
    private enum LedgerItem: Identifiable {
        case shot(Shot, index: Int)
        case puttRun([Shot], startIndex: Int)

        var id: String {
            switch self {
            case let .shot(s, _): return "shot-\(s.id)"
            case let .puttRun(putts, _):
                return "putts-\(putts.first?.id.uuidString ?? "empty")"
            }
        }
    }

    private var ledgerItems: [LedgerItem] {
        var items: [LedgerItem] = []
        var i = 0
        while i < shots.count {
            if shots[i].club == .putter {
                let start = i
                while i < shots.count && shots[i].club == .putter { i += 1 }
                items.append(.puttRun(Array(shots[start..<i]), startIndex: start))
            } else {
                items.append(.shot(shots[i], index: i))
                i += 1
            }
        }
        return items
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    navRow
                        .padding(.horizontal, 24)
                        .padding(.top, 6)

                    if let hole {
                        holeHeading(hole)
                            .padding(.horizontal, 24)
                            .padding(.top, 14)

                        mapBlock(hole: hole)
                            .padding(.horizontal, 20)
                            .padding(.top, 18)

                        ledgerSection
                            .padding(.horizontal, 24)
                            .padding(.top, 24)

                        parSection
                            .padding(.horizontal, 24)
                            .padding(.top, 24)

                        if curatedCourseId != nil {
                            courseSection(hole: hole)
                                .padding(.horizontal, 24)
                                .padding(.top, 24)
                        }

                        if penaltyCount > 0 {
                            penaltyNote
                                .padding(.horizontal, 24)
                                .padding(.top, 20)
                        }
                    } else {
                        Text("NO HOLE TO SHOW")
                            .font(AppFont.stamp)
                            .tracking(1.4)
                            .foregroundStyle(palette.ink3)
                            .padding(.horizontal, 24)
                            .padding(.top, 60)
                    }

                    if let loadError {
                        Text(loadError)
                            .font(AppFont.micro)
                            .tracking(1.2)
                            .foregroundStyle(palette.red)
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                    }

                    Spacer(minLength: 48)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: index) { loadHole() }
        .sheet(isPresented: $showAddShotSheet) {
            AddMissingShotSheet(
                bag: bag,
                currentShotCount: shots.count,
                onAdd: { club, position in addMissingShot(club: club, position: position) },
                onCancel: { showAddShotSheet = false }
            )
        }
        .sheet(item: $exportFile) { ShareSheet(url: $0.url) }
    }

    // MARK: - Nav row

    private var navRow: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text("‹ ROUND")
                    .font(AppFont.metadata)
                    .tracking(1.4)
                    .foregroundStyle(palette.ink)
            }
            Spacer()
            if let hole {
                Stamp(
                    text: hole.confirmedAt != nil ? "Confirmed" : "Unconfirmed",
                    color: hole.confirmedAt != nil ? palette.ink : palette.flag
                )
            }
        }
    }

    // MARK: - Hole heading

    private func holeHeading(_ hole: Hole) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("Hole")
                    .font(.custom(AppFont.serifName, size: 18).italic().weight(.bold))
                    .foregroundStyle(palette.ink2)

                Button {
                    if index > 0 { index -= 1 }
                } label: {
                    Text("‹")
                        .font(.custom(AppFont.serifName, size: 36).weight(.bold))
                        .foregroundStyle(index > 0 ? palette.ink2 : palette.ink3)
                }
                .buttonStyle(.plain)
                .disabled(index == 0)

                Text("\(hole.holeNumber)")
                    .font(AppFont.holeNumeral)
                    .tracking(-3)
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .tabularNumerals()

                Button {
                    if index < holes.count - 1 { index += 1 }
                } label: {
                    Text("›")
                        .font(.custom(AppFont.serifName, size: 36).weight(.bold))
                        .foregroundStyle(index < holes.count - 1 ? palette.ink2 : palette.ink3)
                }
                .buttonStyle(.plain)
                .disabled(index >= holes.count - 1)

                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let p = hole.par {
                        Text("PAR \(p)")
                            .font(AppFont.metadata)
                            .tracking(1.2)
                            .foregroundStyle(palette.ink2)
                    }
                    if let yds = curatedHole?.yards {
                        let f = units.format(yards: Int(yds.rounded()))
                        Text("\(f.value) \(f.unit.uppercased())")
                            .font(AppFont.metadata)
                            .tracking(1.2)
                            .foregroundStyle(palette.ink3)
                    }
                }
            }
            HStack(spacing: 12) {
                Text("\(score)")
                    .font(AppFont.scoreMedium)
                    .foregroundStyle(statusIsRed ? palette.red : palette.ink)
                    .tabularNumerals()
                Stamp(text: statusLabel, color: statusIsRed ? palette.red : palette.ink)
            }
        }
    }

    // MARK: - Map block

    private func mapBlock(hole: Hole) -> some View {
        ZStack(alignment: .topTrailing) {
            EditableHoleMap(
                // While placing tee/green anchors, hide the shot pins so they
                // don't overlap the draggable T and G pins.
                shots: anchorsMode ? [] : shots,
                holeID: hole.id,
                onShotMoved: { shot, coord in moveShot(shot, to: coord) },
                tee: displayTee,
                green: displayGreen,
                onAnchorMoved: anchorsMode ? { kind, coord in
                    saveAnchor(kind, coord)
                } : nil
            )
            .frame(height: 360)
            .overlay(alignment: .bottomLeading) {
                if anchorsMode {
                    Stamp(text: "Drag T & G")
                        .padding(10)
                } else if !hasGPSShots {
                    Stamp(text: "No GPS shots")
                        .padding(10)
                } else {
                    Stamp(text: "Tap a pin to edit")
                        .padding(10)
                }
            }

            // Expand button — top-right
            Button {
                isExpanded = true
            } label: {
                PaperCard(padding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)) {
                    Text("↗ EXPAND")
                        .font(AppFont.stamp)
                        .tracking(1.2)
                        .foregroundStyle(palette.ink)
                }
            }
            .buttonStyle(.plain)
            .padding(10)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(palette.ink, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .paperCardShadow(palette.cardShadow)
        .fullScreenCover(isPresented: $isExpanded) {
            expandedMap(hole: hole)
        }
    }

    private func expandedMap(hole: Hole) -> some View {
        ZStack {
            EditableHoleMap(
                // Same anchor-mode hiding as the inset map.
                shots: anchorsMode ? [] : shots,
                holeID: hole.id,
                onShotMoved: { shot, coord in moveShot(shot, to: coord) },
                tee: displayTee,
                green: displayGreen,
                onAnchorMoved: anchorsMode ? { kind, coord in
                    saveAnchor(kind, coord)
                } : nil
            )
            .ignoresSafeArea()

            VStack {
                HStack(alignment: .top) {
                    Button {
                        isExpanded = false
                    } label: {
                        PaperCard(padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)) {
                            Text("↙ COLLAPSE")
                                .font(AppFont.stamp)
                                .tracking(1.2)
                                .foregroundStyle(palette.ink)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    PaperCard(padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Hole \(hole.holeNumber)")
                                .font(.custom(AppFont.serifName, size: 17).italic().weight(.bold))
                                .foregroundStyle(palette.ink)
                            if let par = hole.par {
                                Text("PAR \(par)")
                                    .font(AppFont.micro)
                                    .tracking(1.4)
                                    .foregroundStyle(palette.ink2)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)

                Spacer()

                HStack {
                    if anchorsMode {
                        PaperCard(padding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)) {
                            Stamp(text: "Drag to fix")
                        }
                    } else {
                        Text("TAP A PIN TO EDIT · DRAG TO REPOSITION")
                            .font(AppFont.micro)
                            .tracking(1.2)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.7), radius: 0, x: 0, y: 1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 28)
            }
        }
        .themedRoot()
    }

    // MARK: - Ledger section

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("The Ledger.")
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(palette.ink)
                Spacer()
                Stamp(text: "\(shots.count) entries")
            }

            VStack(spacing: 0) {
                ledgerHeader
                if shots.isEmpty {
                    HStack {
                        Text("No shots recorded.")
                            .font(AppFont.bodyLarge)
                            .italic()
                            .foregroundStyle(palette.ink3)
                        Spacer()
                    }
                    .padding(.vertical, 14)
                } else {
                    ForEach(ledgerItems) { item in
                        switch item {
                        case let .shot(s, idx):
                            ledgerRow(idx: idx, shot: s)
                        case let .puttRun(putts, startIdx):
                            puttRunSection(putts: putts, startIndex: startIdx)
                        }
                    }
                    ledgerFooter
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
        }
    }

    private var ledgerHeader: some View {
        HStack(spacing: 8) {
            Text("NO.")
                .frame(width: 40, alignment: .leading)
            Text("CLUB")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("YDS")
                .frame(width: 64, alignment: .trailing)
            Text("LIE")
                .frame(width: 80, alignment: .trailing)
        }
        .font(AppFont.micro)
        .tracking(1.4)
        .foregroundStyle(palette.ink2)
        .padding(.vertical, 6)
        .overlay(alignment: .top) { Rectangle().fill(palette.ink).frame(height: 2) }
        .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
    }

    private func ledgerRow(idx: Int, shot: Shot) -> some View {
        let distanceMeters = distance(at: idx)
        let yardsLabel: String = {
            if let m = distanceMeters {
                let f = units.format(yards: Int(Distance.yards(fromMeters: m).rounded()))
                return "\(f.value)"
            }
            return shot.hadGPS ? "—" : "—"
        }()

        return HStack(spacing: 8) {
            Text((idx + 1).roman)
                .font(.custom(AppFont.serifName, size: 16).italic().weight(.bold))
                .foregroundStyle(palette.ink2)
                .frame(width: 40, alignment: .leading)

            Menu {
                ForEach(bag) { club in
                    Button(club.longName) { updateShotClub(shot, club: club) }
                }
                Divider()
                Button("(no club)", role: .destructive) { updateShotClub(shot, club: nil) }
            } label: {
                Text(shot.club?.longName ?? "tap to set club")
                    .font(AppFont.bodyLarge)
                    .foregroundStyle(shot.club == nil ? palette.flag : palette.ink)
                    .italic(shot.club == nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Text(yardsLabel)
                .font(AppFont.monoRow)
                .foregroundStyle(palette.ink)
                .tabularNumerals()
                .frame(width: 64, alignment: .trailing)

            Text(lie(for: shot, at: idx) ?? "—")
                .font(.custom(AppFont.monoName, size: 10).weight(.bold))
                .tracking(1.2)
                .foregroundStyle(palette.ink3)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
        .contextMenu {
            Button("Delete shot", role: .destructive) { deleteShot(shot) }
        }
    }

    /// Collapsed by default; tap toggles inline expansion (renders each putt
    /// via the existing `ledgerRow` so club Menu / delete still work). The
    /// "N Putt(s)" summary itself is read-only — to fix a mis-clubbed putt or
    /// delete one, expand first.
    @ViewBuilder
    private func puttRunSection(putts: [Shot], startIndex: Int) -> some View {
        let runID = putts.first?.id ?? UUID()
        let isExpanded = expandedPuttRuns.contains(runID)
        puttRunRow(putts: putts, startIndex: startIndex, isExpanded: isExpanded)
        if isExpanded {
            ForEach(Array(putts.enumerated()), id: \.element.id) { offset, putt in
                ledgerRow(idx: startIndex + offset, shot: putt)
            }
        }
    }

    private func puttRunRow(putts: [Shot], startIndex: Int, isExpanded: Bool) -> some View {
        let count = putts.count
        let label = count == 1 ? "1 Putt" : "\(count) Putts"
        let runID = putts.first?.id ?? UUID()
        // Run lie: HOLE only if the LAST putt of the run is also the last
        // shot of a confirmed hole (i.e. holed out with a putt). Otherwise
        // GREEN — putters imply on/near the green (see `lie` doc comment).
        let runEndsHole = (startIndex + count == shots.count) && (hole?.confirmedAt != nil)
        let runLie = runEndsHole ? "HOLE" : "GREEN"

        return Button {
            if isExpanded {
                expandedPuttRuns.remove(runID)
            } else {
                expandedPuttRuns.insert(runID)
            }
        } label: {
            HStack(spacing: 8) {
                Text((startIndex + 1).roman)
                    .font(.custom(AppFont.serifName, size: 16).italic().weight(.bold))
                    .foregroundStyle(palette.ink2)
                    .frame(width: 40, alignment: .leading)

                HStack(spacing: 6) {
                    Text(label)
                        .font(AppFont.bodyLarge)
                        .foregroundStyle(palette.ink)
                    Text(isExpanded ? "▾" : "▸")
                        .font(.custom(AppFont.monoName, size: 11).weight(.bold))
                        .foregroundStyle(palette.ink3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // YDS intentionally blank — the whole point of the collapse
                // is that per-putt distances aren't useful at review time.
                Text("—")
                    .font(AppFont.monoRow)
                    .foregroundStyle(palette.ink3)
                    .frame(width: 64, alignment: .trailing)

                Text(runLie)
                    .font(.custom(AppFont.monoName, size: 10).weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(palette.ink3)
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
            .contentShape(Rectangle()) // entire row tappable, not just the text
        }
        .buttonStyle(.plain)
    }

    private var ledgerFooter: some View {
        let total = totalLedgerDistance()
        return HStack {
            Text("Total dist.")
                .font(.custom(AppFont.serifName, size: 17).italic().weight(.bold))
                .foregroundStyle(palette.ink2)
            Spacer()
            Text(total.map { "\($0) \(units.suffix)" } ?? "—")
                .font(AppFont.monoRow)
                .foregroundStyle(palette.ink)
                .tabularNumerals()
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(palette.ink).frame(height: 2) }
    }

    private func totalLedgerDistance() -> Int? {
        var sum = 0
        var hasAny = false
        for idx in 0..<shots.count {
            if let m = distance(at: idx) {
                let yds = Int(Distance.yards(fromMeters: m).rounded())
                let f = units.format(yards: yds)
                sum += f.value
                hasAny = true
            }
        }
        return hasAny ? sum : nil
    }

    // MARK: - Par section

    private var parSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Par")
            HStack {
                Toggle(isOn: $hasPar) {
                    Text("Set par for this hole")
                        .font(AppFont.bodyLarge)
                        .foregroundStyle(palette.ink)
                }
                .tint(palette.flag)
            }
            if hasPar {
                HStack {
                    Stepper(value: $par, in: 3 ... 6) {
                        Text("Par \(par)")
                            .font(AppFont.bodyLarge)
                            .italic()
                            .foregroundStyle(palette.ink)
                    }
                }
            }
            Text("Editing par here updates this hole without re-confirming it.")
                .font(AppFont.micro)
                .tracking(0.8)
                .foregroundStyle(palette.ink3)
        }
        .onChange(of: hasPar) { _, _ in savePar() }
        .onChange(of: par) { _, _ in savePar() }
    }

    // MARK: - Course / anchor section

    private func courseSection(hole: Hole) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Course")

            Toggle(isOn: $anchorsMode) {
                Text("Place tee & green pins")
                    .font(AppFont.bodyLarge)
                    .foregroundStyle(palette.ink)
            }
            .tint(palette.flag)

            if let yds = greenYards {
                HStack {
                    Text("To green from last shot")
                        .font(AppFont.bodyLarge)
                        .italic()
                        .foregroundStyle(palette.ink)
                    Spacer()
                    let f = units.format(yards: yds)
                    Text("\(f.value) \(f.unit)")
                        .font(AppFont.monoRow)
                        .foregroundStyle(palette.ink)
                        .tabularNumerals()
                }
            }

            Button {
                exportAnchors()
            } label: {
                HStack {
                    Stamp(text: "↗ Export anchors")
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Text("Anchors are saved on this device, then exported and merged into the shared course data later — that's what enables distance-to-green here and on the glasses.")
                .font(AppFont.micro)
                .tracking(0.8)
                .foregroundStyle(palette.ink3)
        }
    }

    // MARK: - Penalty note

    private var penaltyNote: some View {
        HStack {
            Stamp(text: "\(penaltyCount) penalty stroke\(penaltyCount == 1 ? "" : "s")", color: palette.flag)
            Spacer()
        }
    }

    // MARK: - Section header helper

    private func sectionHeader(_ label: String) -> some View {
        HStack {
            Text(label.uppercased())
                .font(AppFont.stamp)
                .tracking(1.4)
                .foregroundStyle(palette.ink3)
            Spacer()
            Rectangle().fill(palette.rule).frame(height: 1)
        }
    }

    // MARK: - Persistence (preserved verbatim)

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

    private func deleteShot(_ shot: Shot) {
        do {
            try ShotRepository.deleteAndRenumber(shot)
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

// MARK: - Helper modifier

private extension Text {
    /// Conditional `.italic()` so we don't have to fork the call site.
    func italic(_ on: Bool) -> Text {
        on ? self.italic() : self
    }
}
