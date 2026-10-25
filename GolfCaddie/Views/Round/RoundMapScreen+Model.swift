import CoreLocation
import SwiftUI

// Builds the plain `RoundPanelModel` the layouts draw, from the session, the
// live round and the screen's state.
extension RoundMapScreen {
    func panelState(for session: HoleSession) -> HolePanelState {
        HolePanelState.resolve(mode: mode, isLive: session.isLive, isTracked: session.isTracked,
                               needsEntry: session.needsEntry, isHandScored: session.isHandScored)
    }

    func panelModel(layout: RoundMapLayout) -> RoundPanelModel {
        let shots = session?.shots ?? []
        let penalties = session?.penalties ?? []
        // The hole's own par, else the linked course's (a hole with no row
        // yet — late start, untracked in review — has yards but no par).
        let par = session?.par ?? curatedPar(holeNumber)
        let state = session.map(panelState(for:)) ?? .live
        let length = curatedYards
        let selected = selectedShotID.flatMap { id in shots.first { $0.id == id } }
        let isLive = state == .live || (state == .entry && isViewingLive)
        let liveNumber = liveHoleNumber
        let parText = par.map { String($0) } ?? "—"

        return RoundPanelModel(
            mode: mode,
            layout: layout,
            holeNumber: holeNumber,
            liveHoleNumber: liveNumber,
            par: par,
            holeCaption: RoundMapFormat.tagged(
                RoundMapFormat.holeCaption(par: par, length: length.map { units.format(yards: $0).value },
                                           unit: units.format(yards: 0).unit, roundToPar: nil),
                tag: mode.captionTag),
            // Casual lists the round below, so its compact caption carries
            // the mode instead of the round's to-par.
            compactCaption: RoundMapFormat.tagged(
                RoundMapFormat.holeCaption(par: par, length: length.map { units.format(yards: $0).value },
                                           unit: nil, roundToPar: mode.showsRoundSoFar ? nil : roundToPar),
                tag: mode.captionTag),
            shortCaption: "H\(holeNumber) · P\(parText)",
            canGoPrevious: HoleNavigation.previous(viewing: holeNumber, live: liveNumber) != nil,
            canGoNext: HoleNavigation.next(viewing: holeNumber, live: liveNumber) != nil,
            state: state,
            viewingLive: isViewingLive,
            roundScoreText: roundScoreText,
            courseName: courseName,
            needsCourseLink: curatedCourseId == nil,
            yardage: isViewingLive ? yardage : nil,
            watchDetecting: WatchReachability.isReachable,
            isMarking: isMarking,
            resultText: RoundMapFormat.resultLine(score: session?.score, par: par, putts: session?.putts),
            shotRows: shotRows(shots, isLive: isViewingLive),
            penaltyRows: penalties.map {
                PenaltyRowModel(id: $0.id, title: Self.penaltyTitle($0.type), strokes: $0.strokeCount)
            },
            nextShotText: isViewingLive && mode.tracksShots
                ? "\(shots.count + 1) · \(live?.currentClub?.shortName ?? "—") · NEXT" : nil,
            selectedShotTitle: selected.map { selectedTitle($0, in: shots) },
            clubs: clubChips(selected: selected),
            clubListTitle: selected.map { "SHOT \($0.sequenceNumber)" } ?? (isViewingLive ? "NEXT SHOT" : "TAP A SHOT"),
            clubListHighlighted: selected != nil,
            clubsEnabled: selected != nil || isViewingLive,
            question: question,
            puttsChoice: puttsChoice,
            puttsSummary: PuttsQuestionModel.summary(fullShots: shots.filter { !$0.isPutt }.count,
                                                     penaltyStrokes: session?.penaltyStrokes ?? 0,
                                                     putts: puttsChoice, par: par),
            finishConfirmTitle: PuttsQuestionModel.confirmTitle(holeNumber: holeNumber),
            entry: entryDraft,
            entryTitle: "Score for hole \(holeNumber)",
            entrySummary: entryDraft.summary(par: par),
            entrySaveTitle: HandEntryText.saveTitle(holeNumber: holeNumber,
                                                    alreadyScored: session?.isHandScored ?? false,
                                                    advancesHole: isLive),
            notTrackedText: RoundMapFormat.notTrackedText(holeNumber: holeNumber,
                                                          startingHole: session?.startingHole),
            entryShowsBackToLive: !isViewingLive && live != nil,
            roundSoFar: roundSoFar,
            scoreDraft: scoreDraft,
            controlsVisible: autoHide?.controlsVisible ?? true,
            compassRotation: mapController.rotationFromHoleUp,
            toast: toast
        )
    }

    // MARK: Pieces

    /// TO PIN from the watch-first fix (B35); live hole + linked course only.
    private var yardage: RoundYardage? {
        _ = fixTick // re-read every slow tick (the fix stores are observable too)
        guard let live, let courseId = curatedCourseId,
              let fix = YardageFixAdapter.current(choice: live.currentLocationChoice()),
              let yards = GlassesStateMapper.yardsToGreen(from: fix.coordinate, courseId: courseId,
                                                          holeNumber: holeNumber)
        else { return nil }
        let middle = units.format(yards: yards)
        return RoundYardage(middle: middle.value,
                            front: units.format(yards: max(0, yards - Self.greenHalfDepth)).value,
                            back: units.format(yards: yards + Self.greenHalfDepth).value,
                            unit: middle.unit,
                            sourceText: fix.sourceLabel)
    }

    /// Front / back of the green either side of the middle (no green polygons yet).
    static var greenHalfDepth: Int { 14 }

    /// Hole length from the curated course, yards.
    func curatedPar(_ number: Int) -> Int? {
        guard let courseId = curatedCourseId,
              let course = CourseLookupCache.shared.course(courseId) else { return nil }
        return course.holes.first(where: { $0.number == number })?.par
    }

    private var curatedYards: Int? {
        guard let courseId = curatedCourseId,
              let course = CourseLookupCache.shared.course(courseId),
              let hole = course.holes.first(where: { $0.number == holeNumber }),
              let yards = hole.yards else { return nil }
        return Int(yards.rounded())
    }

    private func shotRows(_ shots: [Shot], isLive: Bool) -> [ShotRowModel] {
        shots.map { shot in
            let club = ClubCatalog.shared.shortName(id: shot.club)
            return ShotRowModel(id: shot.id, number: shot.sequenceNumber, clubText: club ?? "?",
                                distanceText: distanceText(from: shot, in: shots, isLive: isLive),
                                isSelected: shot.id == selectedShotID, needsClub: club == nil)
        }
    }

    /// To the next placed shot; from the last one, to the green on a
    /// finished hole (on the live hole the ball hasn't been hit yet).
    private func distanceText(from shot: Shot, in shots: [Shot], isLive: Bool) -> String? {
        guard let start = Self.coordinate(shot) else { return nil }
        let index = shots.firstIndex { $0.id == shot.id } ?? shots.count
        let next = shots.dropFirst(index + 1).lazy.compactMap(Self.coordinate).first
        let end = next ?? (isLive ? nil
            : GlassesStateMapper.greenCoordinate(courseId: curatedCourseId, holeNumber: holeNumber))
        guard let end else { return nil }
        let yards = Int(Distance.yards(fromMeters: Distance.meters(from: start, to: end)).rounded())
        let formatted = units.format(yards: yards)
        return "\(formatted.value) \(formatted.unit.uppercased())"
    }

    private func selectedTitle(_ shot: Shot, in shots: [Shot]) -> String {
        var parts = ["SHOT \(shot.sequenceNumber)", ClubCatalog.shared.shortName(id: shot.club) ?? "?"]
        if let distance = distanceText(from: shot, in: shots, isLive: isViewingLive) { parts.append(distance) }
        return parts.joined(separator: " · ")
    }

    private func clubChips(selected: Shot?) -> [ClubChipModel] {
        let activeID: String? = selected != nil ? selected?.club : live?.currentClub?.id
        return clubs.map { club in
            let carry = ClubAverages.shared.average(for: club.id) ?? club.defaultYards
            return ClubChipModel(club: club,
                                 carryText: carry > 0 ? "\(units.format(yards: carry).value)" : nil,
                                 isActive: club.id == activeID)
        }
    }

    static func penaltyTitle(_ type: PenaltyType) -> String {
        PenaltyOption.all.first { $0.type == type }?.title ?? type.displayName.uppercased()
    }

    static func coordinate(_ shot: Shot) -> CLLocationCoordinate2D? {
        guard let lat = shot.latitude, let lng = shot.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}
