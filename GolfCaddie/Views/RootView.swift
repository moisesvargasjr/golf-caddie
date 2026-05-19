import SwiftUI

struct RootView: View {
    @State private var bag: [ClubID] = []
    @State private var hasLoadedConfig = false
    @State private var showingBagEditor = false
    @State private var location = LocationManager()
    @State private var controller: RoundController?
    @State private var pendingURLs: [URL] = []
    @State private var glassesServer: GlassesServer?
    @State private var showingGlassesSettings = false
    @AppStorage("glassesServerEnabled") private var glassesEnabled = false

    var body: some View {
        NavigationStack {
            content
        }
        .task {
            location.requestWhenInUse()
            loadConfig()
            // Fire-and-forget curated course-data refresh. Never blocks
            // launch; soft-fails offline; reads at the course use the cache.
            Task { await CourseSyncClient.shared.syncIfStale() }
            if controller == nil {
                let new = RoundController(location: location)
                try? new.restoreActiveRound()
                controller = new
            }
            if glassesServer == nil, let controller {
                let server = GlassesServer(location: location)
                server.attach(controller: controller)
                glassesServer = server
                if glassesEnabled { server.start() }
            }
            processPendingURLs()
        }
        .onOpenURL { url in
            pendingURLs.append(url)
            processPendingURLs()
        }
        .onChange(of: glassesEnabled) { _, enabled in
            if enabled { glassesServer?.start() } else { glassesServer?.stop() }
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
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showingGlassesSettings = true
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                            }
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
                .sheet(isPresented: $showingGlassesSettings) {
                    GlassesSettingsView(onDone: { showingGlassesSettings = false })
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
