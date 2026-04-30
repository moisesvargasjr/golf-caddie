import Foundation

struct ClubConfiguration: Codable, Equatable {
    var bag: [ClubID]

    static let empty = ClubConfiguration(bag: [])

    static let recommendedDefault = ClubConfiguration(bag: [
        .driver, .threeWood, .fiveHybrid,
        .fiveIron, .sixIron, .sevenIron, .eightIron, .nineIron,
        .pitchingWedge, .gapWedge, .sandWedge, .lobWedge,
        .putter
    ])
}
