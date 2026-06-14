import SwiftUI

@main
struct GolfCaddieWatchApp: App {
    @StateObject private var controller = LiveSessionController()

    var body: some Scene {
        WindowGroup {
            LiveRootView()
                .environmentObject(controller)
        }
    }
}
