import Foundation

enum URLSchemeAction: Equatable {
    case markShot
}

enum URLSchemeHandler {
    static let scheme = "golfcaddie"

    static func parse(_ url: URL) -> URLSchemeAction? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        switch url.host?.lowercased() {
        case "mark":
            return .markShot
        default:
            return nil
        }
    }
}
