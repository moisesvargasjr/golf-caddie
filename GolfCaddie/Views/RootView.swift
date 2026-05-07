import SwiftUI

struct RootView: View {
    @State private var bag: [ClubID] = []
    @State private var hasLoadedConfig = false
    @State private var showingBagEditor = false
    @State private var location = LocationManager()
    @State private var controller: RoundController?
    @State private var pendingURLs: [URL] = []

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
            processPendingURLs()
        }
        .onOpenURL { url in
            pendingURLs.append(url)
            processPendingURLs()
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
            ActiveRoundView(controller: controller, location: location, bag: bag)
                .toolbar {
                    if !controller.isActive {
                        ToolbarItem(placement: .topBarLeading) {
                            NavigationLink {
                                RoundListView(bag: bag)
                            } label: {
                                Label("Rounds", systemImage: "list.bullet.rectangle")
                            }
                        }
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

    private func processPendingURLs() {
        guard let controller else { return }
        let urls = pendingURLs
        pendingURLs = []
        for url in urls {
            handle(url: url, controller: controller)
        }
    }

    private func handle(url: URL, controller: RoundController) {
        guard let action = URLSchemeHandler.parse(url) else { return }
        switch action {
        case .markShot:
            Task {
                try? await controller.markShotFromActionButton()
            }
        }
    }
}

#Preview {
    RootView()
}
