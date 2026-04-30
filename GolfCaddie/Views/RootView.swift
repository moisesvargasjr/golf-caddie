import CoreLocation
import SwiftUI

struct RootView: View {
    @State private var bag: [ClubID] = []
    @State private var hasLoadedConfig = false
    @State private var showingBagEditor = false
    @State private var locationManager = CLLocationManager()

    var body: some View {
        NavigationStack {
            content
        }
        .task {
            requestLocationPermission()
            loadConfig()
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
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Text("round not started")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Bag: \(bag.count) club\(bag.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit Bag") { showingBagEditor = true }
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
    }

    private func loadConfig() {
        do {
            bag = try ClubConfigurationRepository.load().bag
        } catch {
            print("Failed to load bag: \(error)")
        }
        hasLoadedConfig = true
    }

    private func requestLocationPermission() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }
}

#Preview {
    RootView()
}
