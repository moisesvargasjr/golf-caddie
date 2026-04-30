import SwiftUI

struct RootView: View {
    @State private var bag: [ClubID] = []
    @State private var hasLoadedConfig = false
    @State private var showingBagEditor = false
    @State private var location = LocationManager()
    @State private var controller: RoundController?

    var body: some View {
        NavigationStack {
            content
        }
        .task {
            location.requestWhenInUse()
            loadConfig()
            if controller == nil {
                let new = RoundController(location: location)
                try? new.restoreActiveRound()
                controller = new
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !hasLoadedConfig {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if bag.isEmpty {
            BagSetupView(initialBag: []) { saved in
                bag = saved
            }
        } else if let controller {
            ActiveRoundView(controller: controller, location: location)
                .toolbar {
                    if !controller.isActive {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Edit Bag") { showingBagEditor = true }
                        }
                    }
                }
                .sheet(isPresented: $showingBagEditor) {
                    NavigationStack {
                        BagSetupView(
                            initialBag: bag,
                            onCancel: { showingBagEditor = false }
                        ) { saved in
                            bag = saved
                            showingBagEditor = false
                        }
                    }
                }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loadConfig() {
        do {
            bag = try ClubConfigurationRepository.load().bag
        } catch {
            print("Failed to load bag: \(error)")
        }
        hasLoadedConfig = true
    }
}

#Preview {
    RootView()
}
