import SwiftUI

@main
struct GolfCaddieApp: App {
    init() {
        _ = Database.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
