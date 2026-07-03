import Foundation

struct ClubConfiguration: Codable, Equatable {
    /// Ordered club-table ids (legacy bags carry old ClubID rawValues — same
    /// strings, so persisted bagJSON decodes unchanged).
    var bag: [String]

    static let empty = ClubConfiguration(bag: [])

    static let recommendedDefault = ClubConfiguration(bag: [
        "driver", "threeWood", "fiveHybrid",
        "fiveIron", "sixIron", "sevenIron", "eightIron", "nineIron",
        "pitchingWedge", "gapWedge", "sandWedge", "lobWedge",
        "putter"
    ])
}
