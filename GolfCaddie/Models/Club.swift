import Foundation

enum ClubID: String, Codable, CaseIterable, Identifiable, Hashable {
    case driver
    case threeWood
    case fiveWood
    case threeHybrid
    case fourHybrid
    case fiveHybrid
    case threeIron
    case fourIron
    case fiveIron
    case sixIron
    case sevenIron
    case eightIron
    case nineIron
    case pitchingWedge
    case gapWedge
    case sandWedge
    case lobWedge
    case putter

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .driver: return "Dr"
        case .threeWood: return "3W"
        case .fiveWood: return "5W"
        case .threeHybrid: return "3H"
        case .fourHybrid: return "4H"
        case .fiveHybrid: return "5H"
        case .threeIron: return "3i"
        case .fourIron: return "4i"
        case .fiveIron: return "5i"
        case .sixIron: return "6i"
        case .sevenIron: return "7i"
        case .eightIron: return "8i"
        case .nineIron: return "9i"
        case .pitchingWedge: return "PW"
        case .gapWedge: return "GW"
        case .sandWedge: return "SW"
        case .lobWedge: return "LW"
        case .putter: return "Pt"
        }
    }

    var longName: String {
        switch self {
        case .driver: return "Driver"
        case .threeWood: return "3 Wood"
        case .fiveWood: return "5 Wood"
        case .threeHybrid: return "3 Hybrid"
        case .fourHybrid: return "4 Hybrid"
        case .fiveHybrid: return "5 Hybrid"
        case .threeIron: return "3 Iron"
        case .fourIron: return "4 Iron"
        case .fiveIron: return "5 Iron"
        case .sixIron: return "6 Iron"
        case .sevenIron: return "7 Iron"
        case .eightIron: return "8 Iron"
        case .nineIron: return "9 Iron"
        case .pitchingWedge: return "Pitching Wedge"
        case .gapWedge: return "Gap Wedge"
        case .sandWedge: return "Sand Wedge"
        case .lobWedge: return "Lob Wedge"
        case .putter: return "Putter"
        }
    }
}
