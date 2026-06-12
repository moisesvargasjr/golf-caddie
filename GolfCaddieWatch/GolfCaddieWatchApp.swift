import SwiftUI

@main
struct GolfCaddieWatchApp: App {
    @StateObject private var controller = SpikeSessionController()

    var body: some Scene {
        WindowGroup {
            TabView {
                RecordingView()
                ControlsView()
            }
            .tabViewStyle(.verticalPage)
            .environmentObject(controller)
        }
    }
}
