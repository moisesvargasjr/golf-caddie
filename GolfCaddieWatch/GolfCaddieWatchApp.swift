import SwiftUI

@main
struct GolfCaddieWatchApp: App {
    @StateObject private var controller = LiveSessionController()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(controller)
                .environmentObject(controller.caddie)
        }
    }
}
