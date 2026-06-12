import SwiftUI

@main
struct GolfCaddieApp: App {
    init() {
        _ = Database.shared
        SpikeSessionReceiver.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
