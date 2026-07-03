import Foundation
import GRDB

enum ShotSource: String, Codable {
    case button
    case actionButton
    case manual
    case glasses
    case watchAuto // auto-detected by the watch swing detector, fused on the phone
    case watchManual // deliberate manual tap on the watch (add-shot / putt counter)
    case reconstructed // laid by end-of-hole reconstruction (B6/B7), not live-logged
}

struct Shot: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "shot"

    var id: UUID
    var holeID: UUID
    var sequenceNumber: Int
    var timestamp: Date
    var latitude: Double?
    var longitude: Double?
    var gpsAccuracy: Double?
    var hadGPS: Bool
    var club: ClubID?
    var source: ShotSource
    var notes: String?
    /// True for a putt — taken on the green, with no full-shot carry distance.
    /// Distinct from `club == .putter` so reconstruction's green-split and the
    /// "no club / no distance" rule have an explicit signal (DESIGN model).
    var isPutt: Bool = false
    /// 0…1 confidence that this is a real, correctly-located stroke. `nil` =
    /// not applicable / unknown (live-logged + manual shots). End-of-hole
    /// reconstruction (B6/B7) sets it and the UI ambers low-confidence pins.
    /// NOT the watch detector's impact-strength proxy (that rides
    /// `SwingEvent.confidence`); keeping the two separate avoids conflating
    /// "hit hard" with "we're sure where this shot is".
    var confidence: Double? = nil
}

extension Shot {
    /// Write-time half of the B28 family rule (putter ⇒ putt, any other known
    /// club ⇒ not a putt): every path that creates a shot or changes its club
    /// derives `isPutt` through here, so a putter picked in the manual-add
    /// sheet or a club edit can't leave a stale flag behind (B31). `explicit`
    /// is the caller's flag, honored only when the club is unknown — the
    /// green-proximity fallback for club-less shots stays reconstruction's job.
    static func derivedIsPutt(club: ClubID?, explicit: Bool = false) -> Bool {
        if let club { return club == .putter }
        return explicit
    }
}
